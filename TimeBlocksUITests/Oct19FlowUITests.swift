//
//  Oct19FlowUITests.swift
//  TimeBlocksUITests
//
//  End-to-end flow: fresh start → plan Oct 19 with School 9am–3pm →
//  set it as the weekday template → drag-drop the template onto other days.
//

import XCTest

final class Oct19FlowUITests: XCTestCase {

    @MainActor
    func testOct19SchoolWeekdayTemplateDragDrop() throws {
        let app = XCUIApplication()
        app.launch()

        // Calendar appears after the splash
        let todayButton = app.buttons["Today"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 10), "calendar should appear")

        // 2) Open Oct 19 and paint School from 9 AM to 3 PM
        let day19 = app.buttons["19"].firstMatch
        XCTAssertTrue(day19.waitForExistence(timeout: 5), "day 19 should exist")
        day19.tap()

        let school = app.buttons.matching(NSPredicate(format: "label CONTAINS 'School'")).firstMatch
        XCTAssertTrue(school.waitForExistence(timeout: 5), "palette should appear")
        school.tap()

        let grid = app.otherElements["dayGrid"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "day grid should be locatable")

        // Rows 9–14 are 9:00–15:00. One vertical drag per quarter column.
        for col in 0..<4 {
            let x = (Double(col) + 0.5) / 4.0
            let from = grid.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 9.5 / 24.0))
            let to = grid.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 14.5 / 24.0))
            from.press(forDuration: 0.05, thenDragTo: to)
        }

        // 3) Zoom back out
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5), "should return to calendar")

        // Long-press Oct 19 → Set as Weekday Template
        day19.press(forDuration: 1.2)
        let setWeekday = app.buttons["Set as Weekday Template"]
        XCTAssertTrue(setWeekday.waitForExistence(timeout: 5), "menu should offer weekday template")
        setWeekday.tap()

        let fromCaption = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'From Oct 19'")).firstMatch
        XCTAssertTrue(fromCaption.waitForExistence(timeout: 5),
                      "STEP 3 RESULT: weekday slot should show 'From Oct 19'")

        // 4) Drag the weekday template onto Oct 21 (blank day → applies immediately)
        let slot = app.staticTexts["Weekday"].firstMatch
        XCTAssertTrue(slot.exists, "weekday slot should exist")
        let day21 = app.buttons["21"].firstMatch
        slot.press(forDuration: 0.5, thenDragTo: day21, withVelocity: .slow, thenHoldForDuration: 0.5)

        // Drop again on the now-planned Oct 21: the overwrite alert appearing
        // proves the first drop actually applied the template.
        slot.press(forDuration: 0.5, thenDragTo: day21, withVelocity: .slow, thenHoldForDuration: 0.5)
        let overwrite = app.buttons["Overwrite"]
        XCTAssertTrue(overwrite.waitForExistence(timeout: 5),
                      "STEP 4 RESULT: second drop on a planned day should ask to overwrite")
        overwrite.tap()

        // And one more drop onto a different blank day (Oct 22)
        let day22 = app.buttons["22"].firstMatch
        slot.press(forDuration: 0.5, thenDragTo: day22, withVelocity: .slow, thenHoldForDuration: 0.5)
    }
}
