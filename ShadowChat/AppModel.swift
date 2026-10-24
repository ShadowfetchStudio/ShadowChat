import AppKit
import Foundation

struct OpenRequest: Equatable {
    var id: String
    var ticket: UUID
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screenName: String
    @Published var signedOn = false
    @Published var buddies: [Buddy]
    @Published var rooms: [Room] = []
    @Published var messages: [String: [ChatMessage]] = [:]
    @Published var engines: [String: TurnEngine] = [:]
    @Published var alert: String?
    @Published var showingKeySheet = false
    @Published var openRequest: OpenRequest?
    @Published var keySaved = false
    @Published var grokModel: String
    @Published var connectPrompt = ""
    @Published var bridgePort = 0
    @Published var connectIssuedAt = Date()
    @Published var joinedGuests: [String] = []
    @Published var connectedGuests: [ConnectedGuest] = []
    @Published var selectedConnectPreset: ConnectPreset = .universal
    @Published var selectedConnectRoom: String = "Lobby"
    @Published var selectedConnectMode: ConnectPromptMode = .full
    @Published var connectBannerText: String = ""
    let version: String

    let database: Database
    private var bridgeServer: LocalBridgeServer?
    private var bridgeToken = ""
    private let bridgeWaitHub = BridgeWaitHub()
    private var handles: [String: TurnHandle] = [:]
    private var loops: [String: Task<Void, Never>] = [:]
    private var signals: [String: AsyncSignal] = [:]

    convenience init() {
        let path = Database.defaultPath()
        if let database = try? Database(path: path) {
            self.init(database: database)
            return
        }
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shadowchat-fallback.sqlite").path
        let database = try! Database(path: fallback)
        self.init(database: database)
    }

    init(database: Database) {
        self.database = database
        let stored = UserDefaults.standard.string(forKey: "ShadowChat.screenName") ?? "Me"
        screenName = stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Me" : stored
        let storedModel = UserDefaults.standard.string(forKey: "ShadowChat.grokModel") ?? CLIPaths.defaultGrokModel
        grokModel = storedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CLIPaths.defaultGrokModel : storedModel
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let enabled = (try? database.enabledParticipants()) ?? [:]
        buddies = ParticipantID.agentOrder.map { id in
            Buddy(id: id, enabled: enabled[id] ?? true, online: false, reason: "Checking…")
        }
        try? database.cancelDanglingStreams()
        var loaded = (try? database.rooms()) ?? []
        if !loaded.contains(where: { $0.kind == .lobby }) {
            if let lobby = try? database.ensureLobby() {
                loaded.insert(lobby, at: 0)
            }
        }
        rooms = loaded
        for room in rooms {
            messages[room.id] = (try? database.messages(roomID: room.id)) ?? []
            var engine = TurnEngine()
            engine.phase = room.runState
            engines[room.id] = engine
        }
        keySaved = KeychainStore.hasKey
        for room in rooms where room.runState == .running {
            ensureLoop(room.id)
        }
        startConnectBridge()
        refreshPresence()
    }

    func signOn() {
        let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            alert = "Enter a screen name."
            return
        }
        screenName = name
        UserDefaults.standard.set(name, forKey: "ShadowChat.screenName")
        signedOn = true
        refreshPresence()
        openLobby()
    }

    func openLobby() {
        if let lobby = rooms.first(where: { $0.kind == .lobby }) {
            requestOpen(lobby.id)
        }
    }

    func signOff() {
        signedOn = false
    }

    func requestOpen(_ roomID: String) {
        if !signedOn {
            let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                alert = "Enter a screen name and sign on."
                return
            }
            screenName = name
            UserDefaults.standard.set(name, forKey: "ShadowChat.screenName")
            signedOn = true
        }
        openRequest = OpenRequest(id: roomID, ticket: UUID())
    }

    func refreshPresence() {
        Task {
            let report = await Task.detached(priority: .utility) {
                PresenceProbe.probe()
            }.value
            apply(report)
            keySaved = KeychainStore.hasKey
        }
    }

    func apply(_ report: [ParticipantID: Presence]) {
        var next = buddies
        for index in next.indices {
            if let presence = report[next[index].id] {
                next[index].online = presence.online
                next[index].reason = presence.reason
            }
        }
        buddies = next
    }

    func sendHuman(roomID: String, plain: String, rtf: Data?) {
        let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, room(roomID) != nil else { return }
        let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = ChatMessage(
            id: UUID().uuidString,
            roomID: roomID,
            sender: .me,
            senderName: name.isEmpty ? "Me" : name,
            body: text,
            rtf: rtf,
            status: .complete,
            createdAt: Date()
        )
        try? database.insertMessage(message)
        append(message)
        guard let room = room(roomID) else { return }
        var engine = engines[roomID] ?? TurnEngine(phase: room.runState)
        var plan = TurnPlanner.plan(
            TurnPlan(
                sender: .me,
                text: text,
                phase: engine.phase,
                roundtable: room.roundtable,
                turnLimit: room.turnLimit,
                roster: buddies
            )
        )
        if plan.isEmpty, engine.phase == .running, let direct = directBuddy(for: room) {
            plan = [direct]
        }
        engine.enqueue(plan)
        engines[roomID] = engine
        ensureLoop(roomID)
        signal(for: roomID).notify()
    }

    func start(roomID: String) {
        var engine = engines[roomID] ?? TurnEngine()
        let plan: [ParticipantID]
        if engine.active == nil, engine.queue.isEmpty,
           let text = TurnPlanner.unansweredHumanText(in: messages[roomID] ?? []),
           let room = room(roomID) {
            var planned = TurnPlanner.plan(
                TurnPlan(
                    sender: .me,
                    text: text,
                    phase: .running,
                    roundtable: room.roundtable,
                    turnLimit: room.turnLimit,
                    roster: buddies
                )
            )
            if planned.isEmpty, let direct = directBuddy(for: room) {
                planned = [direct]
            }
            plan = planned
        } else {
            plan = []
        }
        engine.armIfIdle(plan)
        engines[roomID] = engine
        if var room = room(roomID) {
            room.runState = .running
            save(room)
        }
        ensureLoop(roomID)
        signal(for: roomID).notify()
    }

    func startRoundtable(roomID: String) {
        setRoundtable(roomID: roomID, on: true)
        start(roomID: roomID)
    }

    func pause(roomID: String) {
        var engine = engines[roomID] ?? TurnEngine()
        engine.pause()
        engines[roomID] = engine
        if var room = room(roomID) {
            room.runState = .paused
            save(room)
        }
        signal(for: roomID).notify()
    }

    func stop(roomID: String) {
        var engine = engines[roomID] ?? TurnEngine()
        engine.stop()
        engines[roomID] = engine
        if var room = room(roomID) {
            room.runState = .stopped
            save(room)
        }
        handles[roomID]?.terminate()
        signal(for: roomID).notify()
    }

    func stopAll() {
        for room in rooms {
            stop(roomID: room.id)
        }
        bridgeWaitHub.stopAll()
        bridgeServer?.stop()
        bridgeServer = nil
    }

    func clearRoomMessages(roomID: String) {
        stop(roomID: roomID)
        try? database.clearMessages(roomID: roomID)
        messages[roomID] = []
        bridgeWaitHub.notify(roomID: roomID)
    }

    func setRoundtable(roomID: String, on: Bool) {
        guard var room = room(roomID) else { return }
        room.roundtable = on
        save(room)
    }

    func changeTurnLimit(roomID: String, delta: Int) {
        guard var room = room(roomID) else { return }
        room.turnLimit = min(12, max(1, room.turnLimit + delta))
        save(room)
    }

    func setAllowFileChanges(roomID: String, allowed: Bool) {
        guard var room = room(roomID) else { return }
        if !allowed {
            room.allowFileChanges = false
            save(room)
            return
        }
        guard room.kind == .project, let project = room.projectPath else {
            alert = "File changes stay off until this room has a Git project folder."
            return
        }
        let alertPanel = NSAlert()
        alertPanel.messageText = "Allow file changes in \(room.name)?"
        alertPanel.informativeText = "ShadowChat will create a git worktree under Application Support and run coding agents there. Your project checkout is not the working directory. This stays off unless you confirm."
        alertPanel.addButton(withTitle: "Allow File Changes")
        alertPanel.addButton(withTitle: "Cancel")
        guard alertPanel.runModal() == .alertFirstButtonReturn else { return }
        do {
            let worktree = try WorktreeManager.ensureWorktree(repo: project, roomID: room.id)
            room.worktreePath = worktree
            room.allowFileChanges = true
            save(room)
        } catch {
            alert = error.localizedDescription
        }
    }

    func setEnabled(_ participant: ParticipantID, enabled: Bool) {
        try? database.setEnabled(participant, enabled: enabled)
        guard let index = buddies.firstIndex(where: { $0.id == participant }) else { return }
        buddies[index].enabled = enabled
    }

    func addProjectRoom(path: String) {
        let leaf = URL(fileURLWithPath: path).lastPathComponent
        let room = Room(
            id: UUID().uuidString,
            name: leaf.isEmpty ? "Project" : leaf,
            kind: .project,
            projectPath: path,
            worktreePath: nil,
            allowFileChanges: false,
            roundtable: false,
            turnLimit: 4,
            runState: .stopped,
            createdAt: Date()
        )
        do {
            try database.insertRoom(room)
        } catch {
            alert = error.localizedDescription
            return
        }
        rooms.append(room)
        messages[room.id] = []
        engines[room.id] = TurnEngine()
        requestOpen(room.id)
    }

    func openBuddy(_ participant: ParticipantID) {
        let name = participant.screenName
        if let existing = rooms.first(where: { $0.name == name && $0.projectPath == nil && $0.kind != .lobby }) {
            requestOpen(existing.id)
            return
        }
        let room = Room(
            id: UUID().uuidString,
            name: name,
            kind: .project,
            projectPath: nil,
            worktreePath: nil,
            allowFileChanges: false,
            roundtable: false,
            turnLimit: 4,
            runState: .stopped,
            createdAt: Date()
        )
        do {
            try database.insertRoom(room)
        } catch {
            alert = error.localizedDescription
            return
        }
        rooms.append(room)
        messages[room.id] = []
        engines[room.id] = TurnEngine()
        requestOpen(room.id)
    }

    func saveSetup(screenName: String, modelName: String, apiKey: String) {
        let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            alert = "Enter a screen name."
            return
        }
        let reserved = Set(ParticipantID.agentOrder.map { $0.screenName.lowercased() })
        guard !reserved.contains(name.lowercased()) else {
            alert = "That screen name belongs to an agent."
            return
        }
        self.screenName = name
        UserDefaults.standard.set(name, forKey: "ShadowChat.screenName")
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        grokModel = model.isEmpty ? CLIPaths.defaultGrokModel : model
        UserDefaults.standard.set(grokModel, forKey: "ShadowChat.grokModel")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            saveAPIKey(key)
        }
        rebuildConnectPrompt()
    }

    func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = "Paste an xAI API key first."
            return
        }
        do {
            try KeychainStore.save(trimmed)
            keySaved = true
            refreshPresence()
        } catch {
            alert = error.localizedDescription
        }
    }

    func deleteAPIKey() {
        KeychainStore.delete()
        keySaved = false
        refreshPresence()
    }

    func room(_ id: String) -> Room? {
        rooms.first { $0.id == id }
    }

    func statusLine(roomID: String) -> String {
        guard let room = room(roomID) else { return "" }
        let engine = engines[roomID]
        let phase = (engine?.phase ?? room.runState).label.lowercased()
        let used = turnsUsed(roomID: roomID)
        let speaker = engine?.active.map { " · \($0.screenName)" } ?? ""
        let files = room.allowFileChanges ? " · files on" : ""
        let guests = joinedGuests.isEmpty ? "" : " · bridge: \(joinedGuests.joined(separator: ", "))"
        return "\(room.name)'s Warning Level: \(phase) · turns \(used)/\(room.turnLimit)\(speaker)\(files)\(guests)"
    }

    // MARK: - Connect Prompt & Preset Selection

    func currentEndpoint() -> BridgeEndpoint {
        BridgeEndpoint(host: "127.0.0.1", port: bridgePort, token: bridgeToken)
    }

    func occupantNames() -> [String] {
        var names = [screenName] + ParticipantID.agentOrder.map(\.screenName)
        for guest in joinedGuests where !names.contains(where: { $0.caseInsensitiveCompare(guest) == .orderedSame }) {
            names.append(guest)
        }
        return names
    }

    func rebuildConnectPrompt() {
        guard bridgePort > 0 else { return }
        let endpoint = currentEndpoint()
        connectPrompt = ConnectPrompt.render(
            endpoint: endpoint,
            occupantNames: occupantNames(),
            preset: selectedConnectPreset,
            roomName: selectedConnectRoom,
            mode: selectedConnectMode
        )
    }

    @discardableResult
    func selectConnectPreset(_ preset: ConnectPreset, roomName: String? = nil, mode: ConnectPromptMode? = nil, copyToClipboard: Bool = true) -> String {
        selectedConnectPreset = preset
        if let roomName, !roomName.isEmpty {
            selectedConnectRoom = roomName
        }
        if let mode {
            selectedConnectMode = mode
        }
        rebuildConnectPrompt()
        if copyToClipboard {
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(connectPrompt, forType: .string)
            connectBannerText = "Copied \(preset.displayName) prompt for \(selectedConnectRoom)! Paste (⌘V) into \(preset.displayName)."
        }
        return connectPrompt
    }

    func selectConnectRoom(_ roomName: String, copyToClipboard: Bool = false) {
        selectedConnectRoom = roomName
        rebuildConnectPrompt()
        if copyToClipboard {
            _ = selectConnectPreset(selectedConnectPreset, roomName: roomName, copyToClipboard: true)
        }
    }

    func selectConnectMode(_ mode: ConnectPromptMode, copyToClipboard: Bool = false) {
        selectedConnectMode = mode
        rebuildConnectPrompt()
        if copyToClipboard {
            _ = selectConnectPreset(selectedConnectPreset, mode: mode, copyToClipboard: true)
        }
    }

    @discardableResult
    func copyOneLiner(preset: ConnectPreset? = nil, roomName: String? = nil) -> String {
        let targetPreset = preset ?? selectedConnectPreset
        let targetRoom = roomName ?? selectedConnectRoom
        let command = ConnectPrompt.oneLineCommand(endpoint: currentEndpoint(), preset: targetPreset, roomName: targetRoom)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(command, forType: .string)
        connectBannerText = "Copied 1-line curl command for \(targetPreset.displayName) (\(targetRoom))!"
        return command
    }

    func copyAndOpenApp(for preset: ConnectPreset, roomName: String? = nil) {
        _ = selectConnectPreset(preset, roomName: roomName, copyToClipboard: true)
        if let appURL = preset.installedAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            connectBannerText = "Copied \(preset.displayName) prompt & opened \(appURL.deletingPathExtension().lastPathComponent)! Press ⌘V to paste."
        }
    }

    func isGuestConnected(_ screenNameOrPreset: String) -> Bool {
        guard let canonical = BridgeNames.canonical(screenName: screenNameOrPreset, program: "") else { return false }
        return joinedGuests.contains { $0.caseInsensitiveCompare(canonical) == .orderedSame }
    }

    // MARK: - Internal Helpers

    private func directBuddy(for room: Room) -> ParticipantID? {
        guard room.projectPath == nil, room.kind != .lobby else { return nil }
        guard let buddy = buddies.first(where: { $0.id.screenName.caseInsensitiveCompare(room.name) == .orderedSame }),
              buddy.enabled && buddy.online else {
            return nil
        }
        return buddy.id
    }

    private func save(_ room: Room) {
        guard let index = rooms.firstIndex(where: { $0.id == room.id }) else { return }
        rooms[index] = room
        try? database.saveRoom(room)
    }

    private func append(_ message: ChatMessage) {
        var list = messages[message.roomID] ?? []
        list.append(message)
        messages[message.roomID] = list
        if message.status != .streaming {
            bridgeWaitHub.notify(roomID: message.roomID)
        }
    }

    private func updateStreaming(roomID: String, messageID: String, text: String, status: MessageStatus) {
        var list = messages[roomID] ?? []
        guard let index = list.firstIndex(where: { $0.id == messageID }) else { return }
        list[index].body = text
        list[index].status = status
        messages[roomID] = list
        try? database.updateMessage(id: messageID, body: text, status: status)
        if status != .streaming {
            bridgeWaitHub.notify(roomID: roomID)
        }
    }

    private func ensureLoop(_ roomID: String) {
        if loops[roomID] != nil { return }
        loops[roomID] = Task { [weak self] in
            await self?.loop(roomID)
        }
    }

    private func loop(_ roomID: String) async {
        defer { loops[roomID] = nil }
        let bell = signal(for: roomID)
        var seen = bell.current()
        while !Task.isCancelled {
            var engine = engines[roomID] ?? TurnEngine()
            if let next = engine.dequeueIfIdle() {
                engines[roomID] = engine
                await runTurn(roomID: roomID, participant: next)
                var after = engines[roomID] ?? TurnEngine()
                after.finishCurrent()
                engines[roomID] = after
                continue
            }
            if engine.phase == .stopped, engine.queue.isEmpty, engine.active == nil {
                break
            }
            seen = await bell.wait(after: seen)
        }
    }

    private func runTurn(roomID: String, participant: ParticipantID) async {
        guard let room = room(roomID) else { return }
        if engines[roomID]?.cancelCurrent == true || engines[roomID]?.phase == .stopped {
            return
        }
        let messageID = UUID().uuidString
        let streaming = ChatMessage(
            id: messageID,
            roomID: roomID,
            sender: participant,
            senderName: participant.screenName,
            body: "",
            rtf: nil,
            status: .streaming,
            createdAt: Date()
        )
        try? database.insertMessage(streaming)
        append(streaming)
        if engines[roomID]?.cancelCurrent == true {
            updateStreaming(roomID: roomID, messageID: messageID, text: "", status: .cancelled)
            return
        }

        let history = (messages[roomID] ?? []).filter { $0.id != messageID && $0.status != .streaming }
        let place = directory(for: room)
        let context = AgentTurnContext(
            prompt: makePrompt(participant: participant, room: room, history: history, writable: place.writable),
            cwd: place.cwd,
            writable: place.writable,
            sessionID: try? database.sessionID(roomID: roomID, participant: participant),
            grokModel: grokModel
        )
        let handle = TurnHandle()
        handles[roomID] = handle
        defer { handles[roomID] = nil }

        do {
            let outcome = try await AgentService.run(
                participant: participant,
                context: context,
                handle: handle
            ) { [weak self] text in
                Task { @MainActor in
                    self?.updateStreaming(roomID: roomID, messageID: messageID, text: text, status: .streaming)
                }
            }
            let killed = handle.wasKilled || (engines[roomID]?.cancelCurrent ?? false)
            let status: MessageStatus = killed ? .cancelled : (outcome.text.isEmpty ? .complete : .complete)
            updateStreaming(roomID: roomID, messageID: messageID, text: outcome.text, status: killed ? .cancelled : status)
            if !killed, let sid = outcome.sessionID, !sid.isEmpty {
                try? database.saveSession(roomID: roomID, participant: participant, sessionID: sid)
            }
        } catch let AgentFailure.cancelled(text) {
            let existing = messages[roomID]?.first(where: { $0.id == messageID })?.body ?? ""
            let body = text.count >= existing.count ? text : existing
            updateStreaming(roomID: roomID, messageID: messageID, text: body, status: .cancelled)
        } catch let AgentFailure.failed(text) {
            let existing = messages[roomID]?.first(where: { $0.id == messageID })?.body ?? ""
            let body = existing.isEmpty ? text : existing
            updateStreaming(roomID: roomID, messageID: messageID, text: body, status: .error)
            if text.localizedCaseInsensitiveContains("session") || text.localizedCaseInsensitiveContains("previous_response") {
                try? database.clearSession(roomID: roomID, participant: participant)
            }
        } catch {
            updateStreaming(roomID: roomID, messageID: messageID, text: error.localizedDescription, status: .error)
        }
    }

    private func turnsUsed(roomID: String) -> Int {
        let list = messages[roomID] ?? []
        guard let index = list.lastIndex(where: { BridgeTurnPolicy.isHuman($0, humanScreenName: screenName, joinedGuests: joinedGuests) }) else {
            return 0
        }
        return list.suffix(from: list.index(after: index)).filter { message in
            !BridgeTurnPolicy.isHuman(message, humanScreenName: screenName, joinedGuests: joinedGuests) && message.status != .error
        }.count
    }

    private func directory(for room: Room) -> (cwd: String, writable: Bool) {
        let worktree = room.worktreePath
        let approved = worktree.map { WorktreeManager.isApprovedWorktree($0) } ?? false
        return PermissionGate.directory(
            allowFileChanges: room.allowFileChanges,
            projectPath: room.projectPath,
            worktreePath: worktree,
            worktreeExists: approved,
            scratch: WorktreeManager.scratchDirectory()
        )
    }

    private func makePrompt(participant: ParticipantID, room: Room, history: [ChatMessage], writable: Bool) -> String {
        let lines = history.suffix(16).map { message -> String in
            let body = message.body.count > 1_500 ? String(message.body.prefix(1_500)) + "…" : message.body
            return "\(message.senderName): \(body)"
        }.joined(separator: "\n")
        let clipped = lines.count > 8_000 ? String(lines.suffix(8_000)) : lines
        return PromptText.make(
            speaker: participant.screenName,
            roomName: room.name,
            history: clipped,
            allowFileChanges: writable,
            worktreePath: writable ? room.worktreePath : nil,
            projectPath: room.projectPath
        )
    }

    // MARK: - Localhost Bridge Server

    private func startConnectBridge() {
        let token = BridgeToken.make()
        bridgeToken = token
        let waitHub = bridgeWaitHub
        let server = LocalBridgeServer { [weak self] request in
            guard let self else {
                return BridgeHTTPResponse(status: 503, contentType: "text/plain; charset=utf-8", body: "unavailable")
            }
            return self.handleBridgeRequestOffMain(request, waitHub: waitHub)
        }
        do {
            try server.start()
            bridgeServer = server
            bridgePort = server.port
            let endpoint = BridgeEndpoint(host: "127.0.0.1", port: server.port, token: token)
            let occupants = [screenName] + ParticipantID.agentOrder.map(\.screenName)
            let prompt = ConnectPrompt.render(endpoint: endpoint, occupantNames: occupants)
            connectIssuedAt = Date()
            connectPrompt = prompt
            try? BridgeFiles.write(endpoint: endpoint, prompt: prompt, directory: WorktreeManager.applicationSupport())
        } catch {
            bridgePort = 0
            connectPrompt = "ShadowChat could not open the local bridge on 127.0.0.1. \(error.localizedDescription)"
        }
    }

    nonisolated private func runOnMain<T>(_ block: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { block() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { block() }
        }
    }

    nonisolated private func handleBridgeRequestOffMain(_ request: BridgeHTTPRequest, waitHub: BridgeWaitHub) -> BridgeHTTPResponse {
        if request.path == "/wait" && (request.method == "GET" || request.method == "POST") && !Thread.isMainThread {
            let initial = runOnMain {
                self.prepareBridgeWait(request: request)
            }
            switch initial {
            case .immediate(let response):
                return response
            case .pending(let roomID, let roomName, let screenName, let after, let baselineSeq, var generation, let timeout):
                let deadline = Date().addingTimeInterval(TimeInterval(timeout))
                while Date() < deadline {
                    let woke = waitHub.wait(roomID: roomID, after: generation, until: deadline)
                    if !woke { break }
                    let check = runOnMain {
                        self.checkBridgeWaitWakeup(
                            roomID: roomID,
                            roomName: roomName,
                            screenName: screenName,
                            after: after,
                            baselineSeq: baselineSeq
                        )
                    }
                    switch check {
                    case .ready(let response):
                        return response
                    case .keepWaiting(let nextGen):
                        generation = nextGen
                    }
                }
                return runOnMain {
                    self.finalizeBridgeWaitTimeout(
                        roomID: roomID,
                        roomName: roomName,
                        screenName: screenName,
                        after: after,
                        baselineSeq: baselineSeq
                    )
                }
            }
        }
        return runOnMain {
            self.routeBridge(request)
        }
    }

    private enum WaitPreparation {
        case immediate(BridgeHTTPResponse)
        case pending(roomID: String, roomName: String, screenName: String, after: Int?, baselineSeq: Int, generation: Int, timeout: Int)
    }

    private enum WaitWakeupCheck {
        case ready(BridgeHTTPResponse)
        case keepWaiting(Int)
    }

    private func prepareBridgeWait(request: BridgeHTTPRequest) -> WaitPreparation {
        let info = BridgeRouter.mergedFields(request)
        let token = BridgeRouter.resolveToken(info: info, headers: request.headers)
        guard BridgeInbox.authorize(token, expected: bridgeToken) else {
            return .immediate(.refused)
        }
        let rawName = BridgeRouter.firstNonEmpty(info["screenName"], info["sender"], info["name"], info["program"]) ?? ""
        let roomName = BridgeRouter.firstNonEmpty(info["room"]) ?? "Lobby"
        let after = info["after"].flatMap { Int($0) }
        let rawTimeout = info["timeout"].flatMap { Int($0) } ?? 25
        let timeout = min(max(rawTimeout, 0), 90)

        guard let room = roomNamed(roomName) else {
            return .immediate(BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}"))
        }
        let canonical = BridgeNames.canonical(screenName: rawName, program: "") ?? ""
        if !canonical.isEmpty {
            touchGuest(screenName: canonical, program: canonical, roomName: room.name, isListening: true)
        }
        let roomMessages = messages[room.id] ?? []
        let currentSeq = roomMessages.count
        let shouldReplyNow = BridgeTurnPolicy.shouldReply(
            screenName: canonical,
            messages: roomMessages,
            after: after,
            humanScreenName: screenName,
            joinedGuests: joinedGuests,
            turnLimit: room.turnLimit
        )
        if shouldReplyNow || timeout <= 0 {
            let response = formatWaitResponse(
                room: room,
                messages: roomMessages,
                after: after,
                baselineSeq: after ?? max(0, currentSeq - 8),
                shouldReply: shouldReplyNow,
                timedOut: !shouldReplyNow
            )
            return .immediate(response)
        }
        let generation = bridgeWaitHub.currentGeneration(for: room.id)
        return .pending(
            roomID: room.id,
            roomName: room.name,
            screenName: canonical,
            after: after,
            baselineSeq: currentSeq,
            generation: generation,
            timeout: timeout
        )
    }

    private func checkBridgeWaitWakeup(
        roomID: String,
        roomName: String,
        screenName: String,
        after: Int?,
        baselineSeq: Int
    ) -> WaitWakeupCheck {
        guard let room = room(roomID) else {
            return .ready(BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}"))
        }
        if !screenName.isEmpty {
            touchGuest(screenName: screenName, program: screenName, roomName: roomName, isListening: true)
        }
        let roomMessages = messages[roomID] ?? []
        let shouldReplyNow = BridgeTurnPolicy.shouldReply(
            screenName: screenName,
            messages: roomMessages,
            after: after ?? baselineSeq,
            humanScreenName: self.screenName,
            joinedGuests: joinedGuests,
            turnLimit: room.turnLimit
        )
        if shouldReplyNow || (screenName.isEmpty && roomMessages.count > baselineSeq) {
            return .ready(
                formatWaitResponse(
                    room: room,
                    messages: roomMessages,
                    after: after,
                    baselineSeq: baselineSeq,
                    shouldReply: shouldReplyNow,
                    timedOut: false
                )
            )
        }
        return .keepWaiting(bridgeWaitHub.currentGeneration(for: roomID))
    }

    private func finalizeBridgeWaitTimeout(
        roomID: String,
        roomName: String,
        screenName: String,
        after: Int?,
        baselineSeq: Int
    ) -> BridgeHTTPResponse {
        guard let room = room(roomID) else {
            return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
        }
        if !screenName.isEmpty {
            touchGuest(screenName: screenName, program: screenName, roomName: roomName, isListening: false)
        }
        let roomMessages = messages[roomID] ?? []
        let shouldReplyNow = BridgeTurnPolicy.shouldReply(
            screenName: screenName,
            messages: roomMessages,
            after: after ?? baselineSeq,
            humanScreenName: self.screenName,
            joinedGuests: joinedGuests,
            turnLimit: room.turnLimit
        )
        return formatWaitResponse(
            room: room,
            messages: roomMessages,
            after: after,
            baselineSeq: baselineSeq,
            shouldReply: shouldReplyNow,
            timedOut: !shouldReplyNow
        )
    }

    private func formatWaitResponse(
        room: Room,
        messages: [ChatMessage],
        after: Int?,
        baselineSeq: Int,
        shouldReply: Bool,
        timedOut: Bool
    ) -> BridgeHTTPResponse {
        let seq = messages.count
        let sliceStart: Int
        if let after, after >= 0, after < seq {
            sliceStart = after
        } else if baselineSeq < seq {
            sliceStart = max(0, baselineSeq - 2)
        } else {
            sliceStart = max(0, seq - 12)
        }
        let lines = messages[sliceStart...].suffix(25).map { message -> String in
            let flat = message.body.replacingOccurrences(of: "\n", with: " ")
            let clipped = flat.count > 500 ? String(flat.prefix(500)) + "…" : flat
            return "\(message.senderName): \(clipped)"
        }
        let header = [
            "room: \(room.name)",
            "seq: \(seq)",
            "status: \(timedOut ? "idle" : "message")",
            "should_reply: \(shouldReply ? "yes" : "no")"
        ]
        let text = (header + lines).joined(separator: "\n")
        return BridgeHTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: text + "\n")
    }

    func routeBridge(_ request: BridgeHTTPRequest) -> BridgeHTTPResponse {
        BridgeRouter.handle(request: request, expectedToken: bridgeToken) { action in
            switch action {
            case .join(let screenName, let program):
                return self.registerGuest(screenName: screenName, program: program)
            case .transcript(let room):
                return self.bridgeTranscript(roomName: room)
            case .post(let screenName, let text, let room):
                return self.postGuest(screenName: screenName, text: text, roomName: room)
            case .wait(let screenName, let room, let after, _):
                guard let targetRoom = self.roomNamed(room) else {
                    return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
                }
                let canonical = BridgeNames.canonical(screenName: screenName, program: "") ?? ""
                if !canonical.isEmpty {
                    self.touchGuest(screenName: canonical, program: canonical, roomName: targetRoom.name, isListening: true)
                }
                let roomMessages = self.messages[targetRoom.id] ?? []
                let shouldReplyNow = BridgeTurnPolicy.shouldReply(
                    screenName: canonical,
                    messages: roomMessages,
                    after: after,
                    humanScreenName: self.screenName,
                    joinedGuests: self.joinedGuests,
                    turnLimit: targetRoom.turnLimit
                )
                return self.formatWaitResponse(
                    room: targetRoom,
                    messages: roomMessages,
                    after: after,
                    baselineSeq: after ?? max(0, roomMessages.count - 8),
                    shouldReply: shouldReplyNow,
                    timedOut: !shouldReplyNow
                )
            case .status:
                return self.bridgeStatus()
            case .prompt(let program, let room):
                return self.bridgePrompt(program: program, roomName: room)
            }
        }
    }

    private func touchGuest(screenName: String, program: String, roomName: String, isListening: Bool) {
        if !joinedGuests.contains(where: { $0.caseInsensitiveCompare(screenName) == .orderedSame }) {
            joinedGuests.append(screenName)
        }
        let now = Date()
        if let index = connectedGuests.firstIndex(where: { $0.screenName.caseInsensitiveCompare(screenName) == .orderedSame }) {
            connectedGuests[index].lastSeenAt = now
            connectedGuests[index].roomName = roomName
            connectedGuests[index].isListening = isListening
            if !program.isEmpty {
                connectedGuests[index].program = program
            }
        } else {
            connectedGuests.append(
                ConnectedGuest(
                    screenName: screenName,
                    program: program.isEmpty ? screenName : program,
                    roomName: roomName,
                    lastSeenAt: now,
                    isListening: isListening
                )
            )
        }
    }

    private func registerGuest(screenName: String, program: String) -> BridgeHTTPResponse {
        guard let name = BridgeNames.canonical(screenName: screenName, program: program) else {
            return BridgeHTTPResponse(status: 400, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"screen name required\"}")
        }
        touchGuest(screenName: name, program: program.isEmpty ? name : program, roomName: "Lobby", isListening: true)
        let escaped = BridgeRouter.jsonString(name)
        return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true,\"screenName\":\"\(escaped)\"}")
    }

    private func bridgeTranscript(roomName: String) -> BridgeHTTPResponse {
        guard let room = roomNamed(roomName) else {
            return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
        }
        let roomMessages = messages[room.id] ?? []
        let lines = roomMessages.suffix(40).map { message -> String in
            let flat = message.body.replacingOccurrences(of: "\n", with: " ")
            let clipped = flat.count > 500 ? String(flat.prefix(500)) + "…" : flat
            return "\(message.senderName): \(clipped)"
        }
        let text = (["room: \(room.name)", "seq: \(roomMessages.count)"] + lines).joined(separator: "\n")
        return BridgeHTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: text + "\n")
    }

    private func postGuest(screenName: String, text: String, roomName: String) -> BridgeHTTPResponse {
        do {
            let message = try BridgeInbox.insert(
                database: database,
                rooms: rooms,
                screenName: screenName,
                text: text,
                roomName: roomName
            )
            touchGuest(screenName: message.senderName, program: message.senderName, roomName: roomName, isListening: true)
            append(message)
            planGuest(roomID: message.roomID, text: message.body)
            let escaped = BridgeRouter.jsonString(message.senderName)
            let seq = messages[message.roomID]?.count ?? 0
            return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true,\"screenName\":\"\(escaped)\",\"seq\":\(seq)}")
        } catch BridgeFailure.unknownRoom {
            return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
        } catch {
            return BridgeHTTPResponse(status: 400, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"rejected\"}")
        }
    }

    private func bridgeStatus() -> BridgeHTTPResponse {
        let roomsArray = rooms.map { room -> [String: Any] in
            [
                "name": room.name,
                "kind": room.kind.rawValue,
                "runState": (engines[room.id]?.phase ?? room.runState).rawValue,
                "roundtable": room.roundtable,
                "turnLimit": room.turnLimit,
                "seq": messages[room.id]?.count ?? 0
            ]
        }
        let payload: [String: Any] = [
            "ok": true,
            "host": "127.0.0.1",
            "port": bridgePort,
            "screenName": screenName,
            "joinedGuests": joinedGuests,
            "rooms": roomsArray
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"ok\":true}".utf8)
        let body = String(data: data, encoding: .utf8) ?? "{\"ok\":true}"
        return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: body)
    }

    private func bridgePrompt(program: String, roomName: String) -> BridgeHTTPResponse {
        let preset = ConnectPreset.matching(program)
        let safeRoom = roomNamed(roomName)?.name ?? "Lobby"
        let rendered = ConnectPrompt.render(
            endpoint: currentEndpoint(),
            occupantNames: occupantNames(),
            preset: preset,
            roomName: safeRoom,
            mode: .full
        )
        return BridgeHTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: rendered + "\n")
    }

    private func planGuest(roomID: String, text: String) {
        guard let room = room(roomID) else { return }
        var engine = engines[roomID] ?? TurnEngine(phase: room.runState)
        let plan = BridgeTurnPolicy.plan(text: text, phase: engine.phase, turnLimit: room.turnLimit, roster: buddies)
        guard !plan.isEmpty else { return }
        engine.enqueue(plan)
        engines[roomID] = engine
        ensureLoop(roomID)
        signal(for: roomID).notify()
    }

    private func roomNamed(_ name: String) -> Room? {
        guard let target = BridgeNames.safeRoomName(name) else { return nil }
        return rooms.first { $0.name.compare(target, options: .caseInsensitive) == .orderedSame }
    }

    private func signal(for roomID: String) -> AsyncSignal {
        if let existing = signals[roomID] { return existing }
        let created = AsyncSignal()
        signals[roomID] = created
        return created
    }
}

final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var waiters: [CheckedContinuation<Int, Never>] = []

    func notify() {
        lock.lock()
        generation += 1
        let value = generation
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: value) }
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func wait(after seen: Int) async -> Int {
        await withCheckedContinuation { continuation in
            lock.lock()
            if generation != seen {
                let value = generation
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}
