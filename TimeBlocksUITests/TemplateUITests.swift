//
//  TemplateUITests.swift
//  TimeBlocksUITests
//
//  Reproduces the month-template flow: plan a day, long-press to set it as
//  the weekday/weekend template, and verify the tray shows the template.
//

import XCTest

final class TemplateUITests: XCTestCase {

    @MainActor
    func testSetWeekdayAndWeekendTemplates() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the splash to fade; the calendar's Today button appears
        let todayButton = app.buttons["Today"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 10), "calendar should appear after splash")

        // Open a day cell and paint something so the day is planned
        let dayCell = app.buttons["20"].firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 5), "day cell 20 should exist")
        dayCell.tap()

        let schoolChip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'School'")).firstMatch
        XCTAssertTrue(schoolChip.waitForExistence(timeout: 5), "palette should appear in day editor")
        schoolChip.tap()

        // Tap the middle of the grid to paint one block
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Back to the calendar
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5), "should return to calendar")

        // Long-press the planned day and set it as the weekday template
        dayCell.press(forDuration: 1.2)
        let setWeekday = app.buttons["Set as Weekday Template"]
        XCTAssertTrue(setWeekday.waitForExistence(timeout: 5), "context menu should offer weekday template")
        setWeekday.tap()

        // The weekday tray slot should now show a draggable template
        let dragHints = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'drag onto a day'"))
        XCTAssertTrue(dragHints.firstMatch.waitForExistence(timeout: 5),
                      "weekday template should be stored and shown in the tray")

        // Repeat for the weekend template
        dayCell.press(forDuration: 1.2)
        let setWeekend = app.buttons["Set as Weekend Template"]
        XCTAssertTrue(setWeekend.waitForExistence(timeout: 5), "context menu should offer weekend template")
        setWeekend.tap()

        let bothSet = NSPredicate { _, _ in dragHints.count == 2 }
        let exp = XCTNSPredicateExpectation(predicate: bothSet, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 5), .completed,
                       "both weekday and weekend templates should be shown in the tray")
    }
}
