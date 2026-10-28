import XCTest

final class DocumentPickerTests: XCTestCase {
    @MainActor func testSelectFileImportAndPlay() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = "import-flow-final"; image.lifetime = .keepAlways; add(image)
            print(app.debugDescription)
        }
        let addButton = app.buttons["import-music"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        app.buttons["选择音乐文件"].tap()
        let browse = app.buttons["Browse"].firstMatch
        if browse.waitForExistence(timeout: 5) { browse.tap() }
        print("PICKER AFTER BROWSE:\n" + app.debugDescription)
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
        if !local.waitForExistence(timeout: 5) {
            let back = app.navigationBars.buttons["Browse"].firstMatch
            if back.exists { back.tap() }
        }
        XCTAssertTrue(local.waitForExistence(timeout: 10)); local.tap()
        let appFolder = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "NIC Music")).firstMatch
        XCTAssertTrue(appFolder.waitForExistence(timeout: 10)); appFolder.tap()
        let samples = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Import Samples")).firstMatch
        XCTAssertTrue(samples.waitForExistence(timeout: 10)); samples.tap()
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Wrong Filename")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        for title in ["Open", "Done", "Import"] {
            let finish = app.buttons[title].firstMatch
            if finish.exists && finish.isHittable { finish.tap(); break }
        }
        let result = app.alerts["导入结果"]
        let receivedResult = result.waitForExistence(timeout: 45)
        if !receivedResult { print("IMPORT DID NOT COMPLETE:\n" + app.debugDescription) }
        XCTAssertTrue(receivedResult)
        XCTAssertTrue(result.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已导入 1")).firstMatch.exists)
        result.buttons["好"].tap()
        app.staticTexts["歌曲"].firstMatch.tap()
        let title = app.staticTexts["Metadata Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10)); title.tap()
        let mini = app.buttons["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10)); mini.tap()
        let playback = app.buttons["playback-toggle"]
        XCTAssertTrue(playback.waitForExistence(timeout: 10))
        XCTAssertEqual(playback.label, "暂停")
        playback.tap()
        XCTAssertEqual(playback.label, "播放")
    }
}
