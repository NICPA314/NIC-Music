import XCTest

final class DocumentPickerTests: XCTestCase {
    @MainActor func testSelectFolderImportsAllSongs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let addButton = app.buttons["import-music"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 15)); addButton.tap()
        app.buttons["导入文件夹"].tap()
        let browse = app.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 60)); browse.tap()
        let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "On My iPhone")).firstMatch
        // The provider can remember the folder selected by the preceding test.
        for _ in 0..<4 {
            if local.waitForExistence(timeout: 2) { break }
            let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "On My iPhone", "NIC Music"])).firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(local.waitForExistence(timeout: 10)); local.tap()
        let appFolder = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "NIC Music")).firstMatch
        XCTAssertTrue(appFolder.waitForExistence(timeout: 10)); appFolder.tap()
        let samples = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Import Samples")).firstMatch
        XCTAssertTrue(samples.waitForExistence(timeout: 10)); samples.tap()
        // Folder selection must work without selecting an individual audio file.
        let finish = app.buttons["Open"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: finish)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        finish.tap()
        let result = app.alerts["导入结果"]
        XCTAssertTrue(result.waitForExistence(timeout: 45))
        XCTAssertFalse(result.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "失败")).firstMatch.exists)
        result.buttons["好"].tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "歌曲")).firstMatch.tap()
        for title in ["Metadata Title", "Second Track", "Third Track"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.waitForExistence(timeout: 10))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "folder-import-three-tracks"; screenshot.lifetime = .keepAlways; add(screenshot)
        let search = app.buttons["search-tab"]
        XCTAssertTrue(search.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Only the custom clear-glass dock should be visible")
        XCTAssertGreaterThan(search.frame.midX, app.frame.width * 0.8)
        search.tap()
        let field = app.textFields["music-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("Second Track")
        XCTAssertEqual(field.value as? String, "Second Track", "Typing must keep focus when category cards become search results")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Second Track")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Third Track")).firstMatch.exists)
        let searchImage = XCTAttachment(screenshot: app.screenshot())
        searchImage.name = "search-filtered-results"; searchImage.lifetime = .keepAlways; add(searchImage)
        app.buttons["library-tab"].tap()
        let back = app.navigationBars.buttons["资料库"].firstMatch
        if back.exists { back.tap() }
        let settings = app.buttons["设置"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertFalse(app.staticTexts["AMLL Player 开源项目"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "导入文件夹可")).firstMatch.exists)
        XCTAssertTrue(app.buttons["复制导入诊断"].waitForExistence(timeout: 10))
        let settingsImage = XCTAttachment(screenshot: app.screenshot())
        settingsImage.name = "settings-version-and-diagnostics"; settingsImage.lifetime = .keepAlways; add(settingsImage)
    }

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
        // File-provider UI appears asynchronously on a freshly booted simulator.
        // Do not skip Browse just because its remote view has not arrived yet.
        XCTAssertTrue(browse.waitForExistence(timeout: 60)); browse.tap()
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
        let finish = app.buttons["Open"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 15))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: finish)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        finish.tap()
        let result = app.alerts["导入结果"]
        let receivedResult = result.waitForExistence(timeout: 45)
        if !receivedResult { print("IMPORT DID NOT COMPLETE:\n" + app.debugDescription) }
        XCTAssertTrue(receivedResult)
        XCTAssertTrue(result.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已导入 1")).firstMatch.exists)
        result.buttons["好"].tap()
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "歌曲")).firstMatch.tap()
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Metadata Title")).firstMatch
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
