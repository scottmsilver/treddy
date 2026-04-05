import Foundation

// MARK: - Postel's Law: decode gracefully with missing/null/extra fields

extension KeyedDecodingContainer {
    /// Decode or fall back to default. Never throws on missing keys.
    func val<T: Decodable>(_ type: T.Type, _ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? fallback
    }
}

// MARK: - Status from WebSocket

struct TreadmillStatus: Codable {
    var proxy: Bool = false
    var emulate: Bool = false
    var emuSpeed: Int = 0
    var emuIncline: Double = 0
    var speed: Double? = nil
    var incline: Double? = nil
    var treadmillConnected: Bool = false
    var heartRate: Int = 0
    var hrmConnected: Bool = false
    var hrmDevice: String = ""

    var speedMph: Double { Double(emuSpeed) / 10.0 }
    var inclinePct: Double { emuIncline }

    enum CodingKeys: String, CodingKey {
        case proxy, emulate, speed, incline
        case emuSpeed = "emu_speed"
        case emuIncline = "emu_incline"
        case treadmillConnected = "treadmill_connected"
        case heartRate = "heart_rate"
        case hrmConnected = "hrm_connected"
        case hrmDevice = "hrm_device"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxy = c.val(Bool.self, .proxy, false)
        emulate = c.val(Bool.self, .emulate, false)
        emuSpeed = c.val(Int.self, .emuSpeed, 0)
        emuIncline = c.val(Double.self, .emuIncline, 0)
        speed = try? c.decodeIfPresent(Double.self, forKey: .speed)
        incline = try? c.decodeIfPresent(Double.self, forKey: .incline)
        treadmillConnected = c.val(Bool.self, .treadmillConnected, false)
        heartRate = c.val(Int.self, .heartRate, 0)
        hrmConnected = c.val(Bool.self, .hrmConnected, false)
        hrmDevice = c.val(String.self, .hrmDevice, "")
    }

    init() {}
}

// MARK: - Program state from WebSocket

struct ProgramState: Codable {
    var program: Program? = nil
    var running: Bool = false
    var paused: Bool = false
    var completed: Bool = false
    var currentInterval: Int = 0
    var intervalElapsed: Int = 0
    var totalElapsed: Int = 0
    var totalDuration: Int = 0
    var encouragement: String? = nil

    enum CodingKeys: String, CodingKey {
        case program, running, paused, completed, encouragement
        case currentInterval = "current_interval"
        case intervalElapsed = "interval_elapsed"
        case totalElapsed = "total_elapsed"
        case totalDuration = "total_duration"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        program = try? c.decodeIfPresent(Program.self, forKey: .program)
        running = c.val(Bool.self, .running, false)
        paused = c.val(Bool.self, .paused, false)
        completed = c.val(Bool.self, .completed, false)
        currentInterval = c.val(Int.self, .currentInterval, 0)
        intervalElapsed = c.val(Int.self, .intervalElapsed, 0)
        totalElapsed = c.val(Int.self, .totalElapsed, 0)
        totalDuration = c.val(Int.self, .totalDuration, 0)
        encouragement = try? c.decodeIfPresent(String.self, forKey: .encouragement)
    }

    init() {}
}

struct Program: Codable {
    var name: String = ""
    var manual: Bool = false
    var intervals: [Interval] = []

    enum CodingKeys: String, CodingKey {
        case name, manual, intervals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.val(String.self, .name, "")
        manual = c.val(Bool.self, .manual, false)
        intervals = c.val([Interval].self, .intervals, [])
    }

    init() {}
}

struct Interval: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(duration)-\(speed)-\(incline)" }
    var name: String = ""
    var duration: Double = 0
    var speed: Double = 0
    var incline: Double = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.val(String.self, .name, "")
        duration = c.val(Double.self, .duration, 0)
        speed = c.val(Double.self, .speed, 0)
        incline = c.val(Double.self, .incline, 0)
    }

    init() {}
}

// MARK: - Session from WebSocket

struct SessionState: Codable {
    var active: Bool = false
    var elapsed: Double = 0
    var distance: Double = 0
    var vertFeet: Double = 0
    var calories: Double = 0
    var paused: Bool = false

    enum CodingKeys: String, CodingKey {
        case active, elapsed, distance, calories, paused
        case vertFeet = "vert_feet"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.val(Bool.self, .active, false)
        elapsed = c.val(Double.self, .elapsed, 0)
        distance = c.val(Double.self, .distance, 0)
        vertFeet = c.val(Double.self, .vertFeet, 0)
        calories = c.val(Double.self, .calories, 0)
        paused = c.val(Bool.self, .paused, false)
    }

    init() {}
}

// MARK: - API responses

struct HistoryEntry: Codable, Identifiable {
    var id: String = ""
    var prompt: String = ""
    var program: Program? = nil
    var createdAt: String = ""
    var totalDuration: Double = 0
    var completed: Bool = false
    var lastInterval: Int = 0
    var lastElapsed: Int = 0
    var saved: Bool = false
    var savedWorkoutId: String? = nil
    var lastRunText: String = ""

    enum CodingKeys: String, CodingKey {
        case id, prompt, program, completed, saved
        case savedWorkoutId = "saved_workout_id"
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case lastInterval = "last_interval"
        case lastElapsed = "last_elapsed"
        case lastRunText = "last_run_text"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(String.self, .id, "")
        prompt = c.val(String.self, .prompt, "")
        program = try? c.decodeIfPresent(Program.self, forKey: .program)
        createdAt = c.val(String.self, .createdAt, "")
        totalDuration = c.val(Double.self, .totalDuration, 0)
        completed = c.val(Bool.self, .completed, false)
        lastInterval = c.val(Int.self, .lastInterval, 0)
        lastElapsed = c.val(Int.self, .lastElapsed, 0)
        saved = c.val(Bool.self, .saved, false)
        savedWorkoutId = try? c.decodeIfPresent(String.self, forKey: .savedWorkoutId)
        lastRunText = c.val(String.self, .lastRunText, "")
    }

    init() {}
}

struct SavedWorkout: Codable, Identifiable {
    var id: String = ""
    var name: String = ""
    var program: Program? = nil
    var createdAt: String = ""
    var source: String = ""
    var timesUsed: Int = 0
    var lastUsed: String? = nil
    var totalDuration: Int = 0
    var lastRunText: String = ""
    var usageText: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, program, source
        case createdAt = "created_at"
        case timesUsed = "times_used"
        case lastUsed = "last_used"
        case totalDuration = "total_duration"
        case lastRunText = "last_run_text"
        case usageText = "usage_text"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(String.self, .id, "")
        name = c.val(String.self, .name, "")
        program = try? c.decodeIfPresent(Program.self, forKey: .program)
        createdAt = c.val(String.self, .createdAt, "")
        source = c.val(String.self, .source, "")
        timesUsed = c.val(Int.self, .timesUsed, 0)
        lastUsed = try? c.decodeIfPresent(String.self, forKey: .lastUsed)
        totalDuration = c.val(Int.self, .totalDuration, 0)
        lastRunText = c.val(String.self, .lastRunText, "")
        usageText = c.val(String.self, .usageText, "")
    }

    init() {}
}

struct AppConfig: Codable, Sendable {
    var geminiApiKey: String = ""
    var geminiModel: String = ""
    var geminiLiveModel: String = ""
    var geminiVoice: String = ""
    var systemPrompt: String? = nil
    var smartassAddendum: String? = nil
    var tools: [AppConfigToolGroup]? = nil

    enum CodingKeys: String, CodingKey {
        case geminiApiKey = "gemini_api_key"
        case geminiModel = "gemini_model"
        case geminiLiveModel = "gemini_live_model"
        case geminiVoice = "gemini_voice"
        case systemPrompt = "system_prompt"
        case smartassAddendum = "smartass_addendum"
        case tools
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        geminiApiKey = c.val(String.self, .geminiApiKey, "")
        geminiModel = c.val(String.self, .geminiModel, "")
        geminiLiveModel = c.val(String.self, .geminiLiveModel, "")
        geminiVoice = c.val(String.self, .geminiVoice, "")
        systemPrompt = try? c.decodeIfPresent(String.self, forKey: .systemPrompt)
        smartassAddendum = try? c.decodeIfPresent(String.self, forKey: .smartassAddendum)
        tools = try? c.decodeIfPresent([AppConfigToolGroup].self, forKey: .tools)
    }

    init() {}
}

enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

struct AppConfigToolGroup: Codable, Hashable, Sendable {
    var functionDeclarations: [JSONValue] = []

    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "functionDeclarations"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        functionDeclarations = c.val([JSONValue].self, .functionDeclarations, [])
    }

    init() {}
}

struct HrmDevice: Codable, Hashable, Identifiable {
    var id: String { address }
    var address: String = ""
    var name: String = ""
    var rssi: Int = 0

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = c.val(String.self, .address, "")
        name = c.val(String.self, .name, "")
        rssi = c.val(Int.self, .rssi, 0)
    }

    init() {}
}

struct HrmStatusResponse: Codable {
    var heartRate: Int = 0
    var connected: Bool = false
    var device: String = ""
    var availableDevices: [HrmDevice] = []

    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case connected, device
        case availableDevices = "available_devices"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heartRate = c.val(Int.self, .heartRate, 0)
        connected = c.val(Bool.self, .connected, false)
        device = c.val(String.self, .device, "")
        availableDevices = c.val([HrmDevice].self, .availableDevices, [])
    }

    init() {}
}

struct ScanResultMessage: Codable {
    var type: String = "scan_result"
    var devices: [HrmDevice] = []

    enum CodingKeys: String, CodingKey {
        case type, devices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.val(String.self, .type, "scan_result")
        devices = c.val([HrmDevice].self, .devices, [])
    }

    init() {}
}

struct VoicePromptResponse: Codable {
    var prompt: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompt = c.val(String.self, .prompt, "")
    }

    init() {}
}

struct ToolCallResponse: Codable {
    var ok: Bool = false
    var result: String? = nil
    var error: String? = nil

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.val(Bool.self, .ok, false)
        result = try? c.decodeIfPresent(String.self, forKey: .result)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }

    init() {}
}

struct UserProfile: Codable {
    var id: String = "1"
    var weightLbs: Int = 154
    var vestLbs: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case weightLbs = "weight_lbs"
        case vestLbs = "vest_lbs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(String.self, .id, "1")
        weightLbs = c.val(Int.self, .weightLbs, 154)
        vestLbs = c.val(Int.self, .vestLbs, 0)
    }

    init() {}
}

// MARK: - Multi-user profiles

struct Profile: Codable, Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var color: String = "#d4c4a8"
    var initials: String = "?"
    var weightLbs: Double = 154
    var vestLbs: Double = 0
    var hasAvatar: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, color, initials
        case weightLbs = "weight_lbs"
        case vestLbs = "vest_lbs"
        case hasAvatar = "has_avatar"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(String.self, .id, "")
        name = c.val(String.self, .name, "")
        color = c.val(String.self, .color, "#d4c4a8")
        initials = c.val(String.self, .initials, "?")
        // weight_lbs/vest_lbs may arrive as int or double
        if let d = try? c.decodeIfPresent(Double.self, forKey: .weightLbs) {
            weightLbs = d
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .weightLbs) {
            weightLbs = Double(i)
        }
        if let d = try? c.decodeIfPresent(Double.self, forKey: .vestLbs) {
            vestLbs = d
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .vestLbs) {
            vestLbs = Double(i)
        }
        // has_avatar may arrive as bool, int 0/1, or string
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .hasAvatar) {
            hasAvatar = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .hasAvatar) {
            hasAvatar = i != 0
        }
    }

    init() {}

    /// First name for greetings
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

struct ProfileChangedMessage: Codable {
    var profile: Profile? = nil
    var guestMode: Bool = false

    enum CodingKeys: String, CodingKey {
        case profile
        case guestMode = "guest_mode"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try? c.decodeIfPresent(Profile.self, forKey: .profile)
        guestMode = c.val(Bool.self, .guestMode, false)
    }

    init() {}
}

struct ActiveProfileResponse: Codable {
    var profile: Profile? = nil
    var guestMode: Bool = false

    enum CodingKeys: String, CodingKey {
        case profile
        case guestMode = "guest_mode"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try? c.decodeIfPresent(Profile.self, forKey: .profile)
        guestMode = c.val(Bool.self, .guestMode, false)
    }

    init() {}
}
