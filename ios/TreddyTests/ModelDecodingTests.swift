import XCTest
@testable import Treddy

/// Postel's Law: models must decode gracefully with missing, null, or extra fields.
final class ModelDecodingTests: XCTestCase {

    // MARK: - TreadmillStatus

    func testStatusDecodesFullPayload() throws {
        let json = """
        {"type":"status","proxy":true,"emulate":false,"emu_speed":45,"emu_incline":2.0,
         "speed":null,"incline":null,"treadmill_connected":true,
         "heart_rate":72,"hrm_connected":false,"hrm_device":""}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(TreadmillStatus.self, from: json)
        XCTAssertTrue(status.proxy)
        XCTAssertFalse(status.emulate)
        XCTAssertEqual(status.emuSpeed, 45)
        XCTAssertEqual(status.speedMph, 4.5)
        XCTAssertEqual(status.heartRate, 72)
    }

    func testStatusDecodesMinimalPayload() throws {
        // Server sends only some fields — rest should default
        let json = """
        {"proxy":false,"emulate":true,"emu_speed":0,"emu_incline":0.0,"treadmill_connected":true}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(TreadmillStatus.self, from: json)
        XCTAssertTrue(status.emulate)
        XCTAssertEqual(status.heartRate, 0) // default
        XCTAssertEqual(status.hrmDevice, "") // default
    }

    func testStatusIgnoresExtraFields() throws {
        let json = """
        {"proxy":false,"emulate":false,"emu_speed":0,"emu_incline":0.0,
         "treadmill_connected":true,"heart_rate":0,"hrm_connected":false,"hrm_device":"",
         "some_future_field":"hello","another_one":42}
        """.data(using: .utf8)!
        // Should not throw
        let status = try JSONDecoder().decode(TreadmillStatus.self, from: json)
        XCTAssertFalse(status.proxy)
    }

    // MARK: - ProgramState

    func testProgramDecodesWithIntervals() throws {
        let json = """
        {"program":{"name":"Hill Workout","intervals":[
            {"name":"Warmup","duration":120,"speed":3.0,"incline":0},
            {"name":"Hill","duration":180,"speed":5.0,"incline":5.0}
        ]},"running":true,"paused":false,"completed":false,
         "current_interval":1,"interval_elapsed":30,"total_elapsed":150,"total_duration":300}
        """.data(using: .utf8)!
        let prog = try JSONDecoder().decode(ProgramState.self, from: json)
        XCTAssertEqual(prog.program?.name, "Hill Workout")
        XCTAssertEqual(prog.program?.intervals.count, 2)
        XCTAssertTrue(prog.running)
        XCTAssertEqual(prog.currentInterval, 1)
    }

    func testProgramDecodesWithNullProgram() throws {
        let json = """
        {"program":null,"running":false,"paused":false,"completed":false,
         "current_interval":0,"interval_elapsed":0,"total_elapsed":0,"total_duration":0}
        """.data(using: .utf8)!
        let prog = try JSONDecoder().decode(ProgramState.self, from: json)
        XCTAssertNil(prog.program)
        XCTAssertFalse(prog.running)
    }

    func testProgramDecodesManualFlag() throws {
        let json = """
        {"name":"Manual","manual":true,"intervals":[]}
        """.data(using: .utf8)!
        let program = try JSONDecoder().decode(Program.self, from: json)
        XCTAssertTrue(program.manual)
    }

    // MARK: - HistoryEntry

    func testHistoryEntryDecodesWithLastRun() throws {
        let json = """
        {"id":"123","prompt":"hill workout","program":{"name":"Hills","intervals":[
            {"name":"A","duration":60,"speed":3.0,"incline":0}
        ]},"created_at":"2026-03-28","total_duration":60,"completed":false,
         "last_interval":0,"last_elapsed":0,"saved":true,"last_run_text":"Last run: 2d ago"}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: json)
        XCTAssertEqual(entry.id, "123")
        XCTAssertEqual(entry.program?.name, "Hills")
        XCTAssertTrue(entry.saved)
        XCTAssertEqual(entry.lastRunText, "Last run: 2d ago")
    }

    func testHistoryEntryDecodesEmpty() throws {
        let json = "{}".data(using: .utf8)!
        // Postel's Law: should not crash with empty object
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: json)
        XCTAssertEqual(entry.id, "")
        XCTAssertNil(entry.program)
    }

    // MARK: - SavedWorkout

    func testSavedWorkoutDecodes() throws {
        let json = """
        {"id":"456","name":"Power Walk","program":{"name":"Power Walk","intervals":[
            {"name":"Walk","duration":300,"speed":3.5,"incline":2.0}
        ]},"created_at":"2026-03-28","source":"generated","times_used":5,
         "last_used":"2026-03-27","total_duration":300,"last_run_text":"Used 5 times","usage_text":"5x"}
        """.data(using: .utf8)!
        let w = try JSONDecoder().decode(SavedWorkout.self, from: json)
        XCTAssertEqual(w.name, "Power Walk")
        XCTAssertEqual(w.timesUsed, 5)
    }

    // MARK: - AppConfig / HRM / Voice

    func testAppConfigDecodesSmartassAndTools() throws {
        let json = """
        {
          "gemini_api_key":"k",
          "gemini_model":"m",
          "gemini_live_model":"live",
          "gemini_voice":"Kore",
          "smartass_addendum":"snark",
          "tools":[{"functionDeclarations":[
            {
              "name":"set_speed",
              "description":"Set treadmill speed",
              "parameters":{
                "type":"object",
                "properties":{
                  "value":{"type":"number","minimum":0,"maximum":12}
                },
                "required":["value"]
              }
            },
            {
              "name":"set_incline",
              "description":"Set treadmill incline",
              "parameters":{
                "type":"object",
                "properties":{
                  "value":{"type":"number","minimum":0,"maximum":15}
                },
                "required":["value"]
              }
            }
          ]}]
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(cfg.smartassAddendum, "snark")
        XCTAssertEqual(cfg.tools?.count, 1)
        guard let firstTool = cfg.tools?.first?.functionDeclarations.first,
              let firstToolObject = jsonObject(firstTool),
              let name = jsonString(firstToolObject["name"]),
              let parameters = jsonObject(firstToolObject["parameters"]),
              let required = jsonArray(parameters["required"]),
              let properties = jsonObject(parameters["properties"]),
              let valueSpec = jsonObject(properties["value"]),
              let maximum = jsonNumber(valueSpec["maximum"]) else {
            return XCTFail("Expected nested tool declaration payload")
        }
        XCTAssertEqual(name, "set_speed")
        XCTAssertEqual(required.count, 1)
        XCTAssertEqual(maximum, 12)
    }

    func testHrmStatusResponseDecodesAvailableDevices() throws {
        let json = """
        {
          "heart_rate":72,
          "connected":true,
          "device":"Chest Strap",
          "available_devices":[{"address":"AA:BB:CC:DD:EE:FF","name":"Chest Strap","rssi":-52}]
        }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(HrmStatusResponse.self, from: json)
        XCTAssertEqual(status.availableDevices.count, 1)
        XCTAssertEqual(status.availableDevices.first?.address, "AA:BB:CC:DD:EE:FF")
    }

    func testScanResultMessageDecodesDevices() throws {
        let json = """
        {"devices":[{"address":"AA:BB:CC:DD:EE:FF","name":"Chest Strap","rssi":-52}]}
        """.data(using: .utf8)!
        let message = try JSONDecoder().decode(ScanResultMessage.self, from: json)
        XCTAssertEqual(message.devices.count, 1)
        XCTAssertEqual(message.devices.first?.name, "Chest Strap")
    }

    func testVoicePromptResponseDecodesPrompt() throws {
        let json = """
        {"prompt":"Ask what kind of workout they'd like."}
        """.data(using: .utf8)!
        let prompt = try JSONDecoder().decode(VoicePromptResponse.self, from: json)
        XCTAssertEqual(prompt.prompt, "Ask what kind of workout they'd like.")
    }

    // MARK: - UserProfile

    func testUserProfileWithVest() throws {
        let json = """
        {"id":"1","weight_lbs":180,"vest_lbs":20}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertEqual(user.weightLbs, 180)
        XCTAssertEqual(user.vestLbs, 20)
    }

    func testUserProfileDefaultsVest() throws {
        let json = """
        {"id":"1","weight_lbs":154}
        """.data(using: .utf8)!
        let user = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertEqual(user.vestLbs, 0) // default
    }

    // MARK: - Profile (Postel's Law: weight as int or double, has_avatar as bool or int)

    func testProfileDecodesFullPayload() throws {
        let json = """
        {"id":"abc-123","name":"Scott Silver","color":"#b8c9d4","initials":"SS",
         "weight_lbs":180.0,"vest_lbs":10.0,"has_avatar":true}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertEqual(p.id, "abc-123")
        XCTAssertEqual(p.name, "Scott Silver")
        XCTAssertEqual(p.color, "#b8c9d4")
        XCTAssertEqual(p.initials, "SS")
        XCTAssertEqual(p.weightLbs, 180.0, accuracy: 0.01)
        XCTAssertEqual(p.vestLbs, 10.0, accuracy: 0.01)
        XCTAssertTrue(p.hasAvatar)
        XCTAssertEqual(p.firstName, "Scott")
    }

    func testProfileDecodesWeightAsInt() throws {
        let json = """
        {"id":"1","name":"Test","weight_lbs":154,"vest_lbs":0,"has_avatar":0}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertEqual(p.weightLbs, 154.0, accuracy: 0.01)
        XCTAssertEqual(p.vestLbs, 0.0, accuracy: 0.01)
        XCTAssertFalse(p.hasAvatar)
    }

    func testProfileDecodesHasAvatarAsInt() throws {
        let json = """
        {"id":"1","name":"Test","has_avatar":1}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertTrue(p.hasAvatar)
    }

    func testProfileDecodesEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertEqual(p.id, "")
        XCTAssertEqual(p.initials, "?")
        XCTAssertEqual(p.weightLbs, 154.0, accuracy: 0.01)
        XCTAssertFalse(p.hasAvatar)
    }

    func testProfileIgnoresUnknownFields() throws {
        let json = """
        {"id":"1","name":"Test","created_at":"2026-01-01","updated_at":"2026-04-04","unknown_field":42}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertEqual(p.name, "Test")
    }

    // MARK: - ProfileChangedMessage

    func testProfileChangedDecodesWithProfile() throws {
        let json = """
        {"type":"profile_changed","profile":{"id":"abc","name":"Scott","color":"#d4c4a8","initials":"S",
         "weight_lbs":180,"vest_lbs":0,"has_avatar":false},"guest_mode":false}
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ProfileChangedMessage.self, from: json)
        XCTAssertEqual(msg.profile?.name, "Scott")
        XCTAssertFalse(msg.guestMode)
    }

    func testProfileChangedDecodesGuestMode() throws {
        let json = """
        {"type":"profile_changed","profile":null,"guest_mode":true}
        """.data(using: .utf8)!
        let msg = try JSONDecoder().decode(ProfileChangedMessage.self, from: json)
        XCTAssertNil(msg.profile)
        XCTAssertTrue(msg.guestMode)
    }

    // MARK: - ActiveProfileResponse

    func testActiveProfileResponseDecodes() throws {
        let json = """
        {"profile":{"id":"abc","name":"Scott","color":"#d4c4a8","initials":"S",
         "weight_lbs":180,"vest_lbs":0,"has_avatar":false},"guest_mode":false}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ActiveProfileResponse.self, from: json)
        XCTAssertEqual(resp.profile?.id, "abc")
        XCTAssertFalse(resp.guestMode)
    }

    func testActiveProfileResponseDecodesNull() throws {
        let json = """
        {"profile":null,"guest_mode":true}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(ActiveProfileResponse.self, from: json)
        XCTAssertNil(resp.profile)
        XCTAssertTrue(resp.guestMode)
    }

    // MARK: - ToolCallResponse

    func testToolCallResponseOk() throws {
        let json = """
        {"ok":true,"result":"[{\\"cnt\\": 10}]"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ToolCallResponse.self, from: json)
        XCTAssertTrue(r.ok)
        XCTAssertNotNil(r.result)
    }

    func testToolCallResponseError() throws {
        let json = """
        {"ok":false,"error":"Query error: syntax error"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(ToolCallResponse.self, from: json)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.error, "Query error: syntax error")
    }
}

private func jsonObject(_ value: JSONValue) -> [String: JSONValue]? {
    if case .object(let object) = value { return object }
    return nil
}

private func jsonObject(_ value: JSONValue?) -> [String: JSONValue]? {
    guard let value else { return nil }
    return jsonObject(value)
}

private func jsonArray(_ value: JSONValue?) -> [JSONValue]? {
    guard let value, case .array(let array) = value else { return nil }
    return array
}

private func jsonString(_ value: JSONValue?) -> String? {
    guard let value, case .string(let string) = value else { return nil }
    return string
}

private func jsonNumber(_ value: JSONValue?) -> Double? {
    guard let value else { return nil }
    switch value {
    case .int(let intValue):
        return Double(intValue)
    case .double(let doubleValue):
        return doubleValue
    default:
        return nil
    }
}
