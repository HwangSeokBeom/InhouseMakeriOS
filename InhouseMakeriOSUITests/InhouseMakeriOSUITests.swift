import XCTest

final class InhouseMakeriOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testInviteSheetAndTenMemberMatchFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-group-invite-flow"]
        app.launch()

        XCTAssertTrue(app.navigationBars["롤내전모임"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["멤버 초대"].exists)

        app.buttons["멤버 초대"].tap()

        XCTAssertTrue(app.staticTexts["팀원 추가"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["닫기"].exists)
        XCTAssertTrue(app.textFields["닉네임으로 팀원 검색"].exists)
        XCTAssertTrue(app.staticTexts["바로 추가하기"].exists)
        XCTAssertTrue(app.staticTexts["최근 검색"].exists)
        XCTAssertTrue(app.staticTexts["선택된 팀원"].exists)

        let inviteButton = app.buttons["팀원 추가"]
        XCTAssertTrue(inviteButton.exists)
        XCTAssertFalse(inviteButton.isEnabled)

        let searchField = app.textFields["닉네임으로 팀원 검색"]
        searchField.tap()
        searchField.typeText("none")
        XCTAssertTrue(app.staticTexts["검색 결과가 없어요."].waitForExistence(timeout: 3))

        app.buttons["검색어 지우기"].tap()
        searchField.tap()
        searchField.typeText("alpha")

        XCTAssertTrue(app.staticTexts["검색 결과"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["나"].exists)
        XCTAssertTrue(app.staticTexts["이미 멤버"].exists)
        XCTAssertTrue(app.staticTexts["초대 가능"].exists)

        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["멤버 초대"].waitForExistence(timeout: 2))

        app.buttons["내전 생성"].tap()
        XCTAssertTrue(app.navigationBars["내전 로비"].waitForExistence(timeout: 5))

        let manageMembersButton = app.navigationBars["내전 로비"].buttons["참가자 관리 메뉴"]
        XCTAssertTrue(manageMembersButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["테스터"].waitForExistence(timeout: 3))
        manageMembersButton.tap()

        XCTAssertTrue(app.navigationBars["참가자 추가"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["선택 가능 9명"].exists)

        app.buttons["남은 멤버 전체 선택"].tap()
        XCTAssertTrue(app.staticTexts["선택 9명"].waitForExistence(timeout: 2))
        app.buttons["참가자 추가"].tap()
        let closeButton = app.buttons["닫기"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        }

        XCTAssertTrue(app.staticTexts["10명이 모였습니다. 자동 팀 생성을 실행할 수 있습니다"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MID / TOP"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["94"].waitForExistence(timeout: 3))

        let autoBalanceButton = app.buttons["자동 팀 생성"]
        XCTAssertTrue(autoBalanceButton.waitForExistence(timeout: 3))
        XCTAssertTrue(autoBalanceButton.isEnabled)

        let manualAssignButton = app.buttons["수동 배치"]
        XCTAssertTrue(manualAssignButton.exists)
        XCTAssertTrue(manualAssignButton.isEnabled)

        autoBalanceButton.tap()
        XCTAssertTrue(app.navigationBars["팀 밸런스 결과"].waitForExistence(timeout: 5))

        app.buttons["이 조합으로 확정"].tap()
        XCTAssertTrue(app.navigationBars["경기 결과 입력"].waitForExistence(timeout: 5))

        app.buttons["내 계정에 저장"].tap()
        XCTAssertTrue(app.staticTexts["MVP를 선택해 주세요."].waitForExistence(timeout: 3))

        app.buttons["테스터"].tap()
        app.buttons["내 계정에 저장"].tap()
        XCTAssertTrue(app.staticTexts["라인별 승패를 모두 선택해 주세요. 누락: TOP, JGL, MID, BOT"].waitForExistence(timeout: 3))
    }
}
