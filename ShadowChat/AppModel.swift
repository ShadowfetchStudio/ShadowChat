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
    let version: String

    let database: Database
    private var bridgeServer: LocalBridgeServer?
    private var bridgeToken = ""
    private var joinedGuests: [String] = []
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
        let plan = TurnPlanner.plan(
            TurnPlan(
                sender: .me,
                text: text,
                phase: engine.phase,
                roundtable: room.roundtable,
                turnLimit: room.turnLimit,
                roster: buddies
            )
        )
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
            plan = TurnPlanner.plan(
                TurnPlan(
                    sender: .me,
                    text: text,
                    phase: .running,
                    roundtable: room.roundtable,
                    turnLimit: room.turnLimit,
                    roster: buddies
                )
            )
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
        bridgeServer?.stop()
        bridgeServer = nil
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
        return "\(room.name)'s Warning Level: \(phase) · turns \(used)/\(room.turnLimit)\(speaker)\(files)"
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
    }

    private func updateStreaming(roomID: String, messageID: String, text: String, status: MessageStatus) {
        var list = messages[roomID] ?? []
        guard let index = list.firstIndex(where: { $0.id == messageID }) else { return }
        list[index].body = text
        list[index].status = status
        messages[roomID] = list
        try? database.updateMessage(id: messageID, body: text, status: status)
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
        guard let index = list.lastIndex(where: { $0.sender == .me }) else { return 0 }
        return list.suffix(from: list.index(after: index)).filter { message in
            ParticipantID.agentOrder.contains(message.sender) && message.status != .error
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


    private func startConnectBridge() {
        let token = BridgeToken.make()
        bridgeToken = token
        let server = LocalBridgeServer { [weak self] request in
            guard let self else {
                return BridgeHTTPResponse(status: 503, contentType: "text/plain; charset=utf-8", body: "unavailable")
            }
            if Thread.isMainThread {
                return MainActor.assumeIsolated { self.routeBridge(request) }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { self.routeBridge(request) }
            }
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

    private func routeBridge(_ request: BridgeHTTPRequest) -> BridgeHTTPResponse {
        BridgeRouter.handle(request: request, expectedToken: bridgeToken) { action in
            switch action {
            case .join(let screenName, let program):
                return self.registerGuest(screenName: screenName, program: program)
            case .transcript(let room):
                return self.bridgeTranscript(roomName: room)
            case .post(let screenName, let text, let room):
                return self.postGuest(screenName: screenName, text: text, roomName: room)
            }
        }
    }

    private func registerGuest(screenName: String, program: String) -> BridgeHTTPResponse {
        guard let name = BridgeNames.canonical(screenName: screenName, program: program) else {
            return BridgeHTTPResponse(status: 400, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"screen name required\"}")
        }
        if !joinedGuests.contains(name) {
            joinedGuests.append(name)
        }
        let escaped = BridgeRouter.jsonString(name)
        return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true,\"screenName\":\"\(escaped)\"}")
    }

    private func bridgeTranscript(roomName: String) -> BridgeHTTPResponse {
        guard let room = roomNamed(roomName) else {
            return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
        }
        let lines = (messages[room.id] ?? []).suffix(40).map { message -> String in
            let flat = message.body.replacingOccurrences(of: "\n", with: " ")
            let clipped = flat.count > 500 ? String(flat.prefix(500)) + "…" : flat
            return "\(message.senderName): \(clipped)"
        }
        let text = (["room: \(room.name)"] + lines).joined(separator: "\n")
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
            append(message)
            planGuest(roomID: message.roomID, text: message.body)
            let escaped = BridgeRouter.jsonString(message.senderName)
            return BridgeHTTPResponse(status: 200, contentType: "application/json; charset=utf-8", body: "{\"ok\":true,\"screenName\":\"\(escaped)\"}")
        } catch BridgeFailure.unknownRoom {
            return BridgeHTTPResponse(status: 404, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"unknown room\"}")
        } catch {
            return BridgeHTTPResponse(status: 400, contentType: "application/json; charset=utf-8", body: "{\"ok\":false,\"error\":\"rejected\"}")
        }
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
