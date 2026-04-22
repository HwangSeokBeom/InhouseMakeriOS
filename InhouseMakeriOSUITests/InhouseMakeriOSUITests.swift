import XCTest

final class InhouseMakeriOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testNotificationPermissionDoesNotAutoPromptOnLaunch() throws {
        let app = launchNotificationPermissionFlowApp(
            currentStatus: "notDetermined",
            requestResult: "authorized"
        )

        XCTAssertTrue(app.staticTexts["설정"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts["푸시 알림을 켤까요?"].exists)
        let status = app.staticTexts["settings.notificationPermission.status"]
        XCTAssertTrue(scrollToExisting(status, in: app))
        XCTAssertTrue(waitForLabel(status, equals: "허용 전", timeout: 2))
    }

    func testNotificationPermissionFlowStartsOnlyAfterCTA() throws {
        let app = launchNotificationPermissionFlowApp(
            currentStatus: "notDetermined",
            requestResult: "authorized"
        )

        XCTAssertFalse(app.alerts["푸시 알림을 켤까요?"].exists)
        let primaryButton = app.buttons["settings.notificationPermission.primaryButton"]
        XCTAssertTrue(scrollToHittable(primaryButton, in: app))
        primaryButton.tap()

        XCTAssertTrue(app.alerts["푸시 알림을 켤까요?"].waitForExistence(timeout: 3))
    }

    func testNotificationPermissionDeniedStateShowsSettingsGuidance() throws {
        let app = launchNotificationPermissionFlowApp(
            currentStatus: "notDetermined",
            requestResult: "denied"
        )

        let primaryButton = app.buttons["settings.notificationPermission.primaryButton"]
        XCTAssertTrue(scrollToHittable(primaryButton, in: app))
        primaryButton.tap()

        let permissionAlert = app.alerts["푸시 알림을 켤까요?"]
        XCTAssertTrue(permissionAlert.waitForExistence(timeout: 3))
        permissionAlert.buttons["계속"].tap()

        XCTAssertTrue(app.staticTexts["settings.notificationPermission.status"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["settings.notificationPermission.status"].label, "설정 필요")
        XCTAssertTrue(app.buttons["settings.notificationPermission.primaryButton"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["settings.notificationPermission.primaryButton"].label, "설정 열기")
        XCTAssertTrue(app.staticTexts["설정에서 알림 허용이 필요해요"].exists)
    }

    func testNotificationPermissionAuthorizedStateShowsEnabledUI() throws {
        let app = launchNotificationPermissionFlowApp(
            currentStatus: "notDetermined",
            requestResult: "authorized"
        )

        let primaryButton = app.buttons["settings.notificationPermission.primaryButton"]
        XCTAssertTrue(scrollToHittable(primaryButton, in: app))
        primaryButton.tap()

        let permissionAlert = app.alerts["푸시 알림을 켤까요?"]
        XCTAssertTrue(permissionAlert.waitForExistence(timeout: 3))
        permissionAlert.buttons["계속"].tap()

        XCTAssertTrue(app.staticTexts["settings.notificationPermission.status"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["settings.notificationPermission.status"].label, "활성")
        XCTAssertTrue(app.staticTexts["푸시 알림이 켜져 있어요"].exists)
        XCTAssertFalse(app.buttons["settings.notificationPermission.primaryButton"].exists)
    }

    func testMemberInviteSheetHeaderUsesUpdatedContract() throws {
        let app = launchGroupInviteFlowApp()

        let inviteButton = app.buttons["멤버 초대"]
        XCTAssertTrue(waitForHittable(inviteButton, timeout: 5))
        inviteButton.tap()

        assertMemberInviteSheetHeader(in: app)
    }

    func testGroupDetailOverflowShowsManagementActionSheet() throws {
        let app = launchGroupInviteFlowApp()

        let overflowButton = app.buttons["groupDetail.overflowButton"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        XCTAssertTrue(app.otherElements["groupDetail.managementActionSheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["groupDetail.managementActionSheet.edit"].exists)
        XCTAssertTrue(app.buttons["groupDetail.managementActionSheet.delete"].exists)
        XCTAssertTrue(app.buttons["groupDetail.managementActionSheet.cancel"].exists)
    }

    func testMatchLobbyOverflowShowsManagementActionSheet() throws {
        let app = launchGroupInviteFlowApp()

        enterMatchLobby(in: app)

        let overflowButton = app.buttons["matchLobby.manageToolbar"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        XCTAssertTrue(app.otherElements["matchLobby.managementActionSheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["matchLobby.managementActionSheet.inviteMembers"].exists)
        XCTAssertTrue(app.buttons["matchLobby.managementActionSheet.edit"].exists)
        XCTAssertTrue(app.buttons["matchLobby.managementActionSheet.delete"].exists)
        XCTAssertTrue(app.buttons["matchLobby.managementActionSheet.cancel"].exists)
    }

    func testMatchLobbyManagementActionSheetInvitePresentsMemberInviteSheet() throws {
        let app = launchGroupInviteFlowApp()

        enterMatchLobby(in: app)

        let overflowButton = app.buttons["matchLobby.manageToolbar"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        let inviteAction = app.buttons["matchLobby.managementActionSheet.inviteMembers"]
        XCTAssertTrue(waitForHittable(inviteAction, timeout: 3))
        inviteAction.tap()

        assertMemberInviteSheetHeader(in: app)
    }

    func testMatchLobbyManagementActionSheetEditShowsEditFlowNotice() throws {
        let app = launchGroupInviteFlowApp()

        enterMatchLobby(in: app)

        let overflowButton = app.buttons["matchLobby.manageToolbar"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        let editAction = app.buttons["matchLobby.managementActionSheet.edit"]
        XCTAssertTrue(waitForHittable(editAction, timeout: 3))
        editAction.tap()

        XCTAssertTrue(app.alerts["내전 수정은 준비 중입니다"].waitForExistence(timeout: 3))
    }

    func testMatchLobbyManagementActionSheetDeleteShowsDeleteConfirmation() throws {
        let app = launchGroupInviteFlowApp()

        enterMatchLobby(in: app)

        let overflowButton = app.buttons["matchLobby.manageToolbar"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        let deleteAction = app.buttons["matchLobby.managementActionSheet.delete"]
        XCTAssertTrue(waitForHittable(deleteAction, timeout: 3))
        deleteAction.tap()

        XCTAssertTrue(app.alerts["이 내전을 삭제할까요?"].waitForExistence(timeout: 3))
    }

    func testRecruitBoardMemberPostOverflowShowsManagementActionSheet() throws {
        let app = launchRecruitManagementFlowApp()

        let overflowButton = app.buttons["recruitPost.card.debug-member-recruit-post.overflowButton"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        XCTAssertTrue(app.otherElements["recruitPost.managementActionSheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.edit"].exists)
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.delete"].exists)
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.cancel"].exists)
    }

    func testRecruitBoardOpponentPostOverflowShowsManagementActionSheet() throws {
        let app = launchRecruitManagementFlowApp()

        let opponentTypeButton = app.buttons["상대팀 모집"]
        XCTAssertTrue(waitForHittable(opponentTypeButton, timeout: 5))
        opponentTypeButton.tap()

        let overflowButton = app.buttons["recruitPost.card.debug-opponent-recruit-post.overflowButton"]
        XCTAssertTrue(waitForHittable(overflowButton, timeout: 5))
        overflowButton.tap()

        XCTAssertTrue(app.otherElements["recruitPost.managementActionSheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.edit"].exists)
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.delete"].exists)
        XCTAssertTrue(app.buttons["recruitPost.managementActionSheet.cancel"].exists)
    }

    func testInviteSheetAndTenMemberMatchFlow() throws {
        let app = launchGroupInviteFlowApp()

        XCTAssertTrue(app.navigationBars["롤내전모임"].waitForExistence(timeout: 5))

        enterMatchLobby(in: app)

        let participantCountLabel = app.otherElements["matchLobby.participantCount"]
        XCTAssertEqual(participantCountLabel.label, "1/10")

        let manageMembersButton = app.buttons["matchLobby.manageToolbar"]
        XCTAssertTrue(app.buttons["matchLobby.autoBalanceButton"].waitForExistence(timeout: 5))
        manageMembersButton.tap()

        XCTAssertTrue(app.otherElements["matchLobby.managementActionSheet"].waitForExistence(timeout: 3))
        let inviteAction = app.buttons["matchLobby.managementActionSheet.inviteMembers"]
        XCTAssertTrue(waitForHittable(inviteAction, timeout: 3))
        inviteAction.tap()

        let lobbyInviteSheet = app.otherElements["memberInviteSheet.root"]
        XCTAssertTrue(lobbyInviteSheet.waitForExistence(timeout: 3))
        let lobbyInviteSubmitButton = app.buttons["memberInviteSheet.submitButton"]
        XCTAssertFalse(lobbyInviteSubmitButton.isEnabled)

        app.buttons["남은 멤버 전체 선택"].tap()
        XCTAssertTrue(waitForEnabled(lobbyInviteSubmitButton, timeout: 2))
        lobbyInviteSubmitButton.tap()

        XCTAssertTrue(waitForNonExistence(lobbyInviteSheet, timeout: 3))
        XCTAssertTrue(waitForLabel(participantCountLabel, equals: "10/10", timeout: 5))

        let autoBalanceButton = app.buttons["matchLobby.autoBalanceButton"]
        XCTAssertTrue(waitForEnabled(autoBalanceButton, timeout: 10))

        let manualAssignButton = app.buttons["matchLobby.manualAssignButton"]
        XCTAssertTrue(waitForEnabled(manualAssignButton, timeout: 3))

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

    private func launchGroupInviteFlowApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-group-invite-flow"]
        app.launch()
        return app
    }

    private func launchRecruitManagementFlowApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-recruit-management-flow"]
        app.launch()
        return app
    }

    private func launchNotificationPermissionFlowApp(
        currentStatus: String,
        requestResult: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-test-notification-permission-flow",
            "-ui-test-notification-auth-status",
            currentStatus,
            "-ui-test-notification-request-result",
            requestResult,
        ]
        app.launch()
        return app
    }

    private func enterMatchLobby(in app: XCUIApplication) {
        let createMatchButton = app.buttons["내전 생성"]
        if !waitForHittable(createMatchButton, timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(waitForHittable(createMatchButton, timeout: 5))
        createMatchButton.tap()

        XCTAssertTrue(app.otherElements["matchLobby.root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["matchLobby.participantCount"].waitForExistence(timeout: 5))
    }

    private func assertMemberInviteSheetHeader(in app: XCUIApplication) {
        let inviteSheet = app.otherElements["memberInviteSheet.root"]
        XCTAssertTrue(inviteSheet.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["memberInviteSheet.title"].exists)
        XCTAssertFalse(app.buttons["memberInviteSheet.closeButton"].exists)
        XCTAssertTrue(app.textFields["memberInviteSheet.searchField"].exists)
        XCTAssertTrue(app.buttons["memberInviteSheet.submitButton"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)
        XCTAssertFalse(app.navigationBars["팀원 추가"].exists)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isEnabled
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return !element.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.isHittable
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, equals label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.label == label
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func scrollToExisting(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> Bool {
        if element.waitForExistence(timeout: 1) {
            return true
        }

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<maxSwipes {
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return element.exists
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> Bool {
        if waitForHittable(element, timeout: 1) {
            return true
        }

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<maxSwipes {
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
            if waitForHittable(element, timeout: 1) {
                return true
            }
        }
        return element.exists && element.isHittable
    }
}
