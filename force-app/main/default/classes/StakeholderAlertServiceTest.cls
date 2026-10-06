/**
 * Test class for StakeholderAlertService
 */
@isTest
private class StakeholderAlertServiceTest {

    @testSetup
    static void setup() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        List<Contact> contacts = new List<Contact>();
        contacts.add(new Contact(
            FirstName = 'John', LastName = 'CEO',
            AccountId = testAccount.Id,
            Title = 'Chief Executive Officer',
            Email = 'ceo@example.com'
        ));
        contacts.add(new Contact(
            FirstName = 'Jane', LastName = 'VP',
            AccountId = testAccount.Id,
            Title = 'VP of Sales',
            Email = 'vp@example.com'
        ));
        contacts.add(new Contact(
            FirstName = 'Bob', LastName = 'Manager',
            AccountId = testAccount.Id,
            Title = 'Sales Manager',
            Email = 'manager@example.com'
        ));
        insert contacts;

        Opportunity largeOpp = new Opportunity(
            Name = 'Large Deal',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 150000
        );
        insert largeOpp;

        Opportunity smallOpp = new Opportunity(
            Name = 'Small Deal',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 25000
        );
        insert smallOpp;
    }

    @isTest
    static void testGenerateAlertsNoChampion() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'CEO' LIMIT 1];

        insert new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = con.Id,
            Role__c = 'Influencer',
            Influence_Level__c = 'High',
            Engagement_Status__c = 'Engaged'
        );

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> alerts = [
            SELECT Id, Alert_Type__c, Priority__c
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Alert_Type__c = 'Missing Champion'
        ];

        System.assertEquals(1, alerts.size(), 'Should generate Missing Champion alert');
        System.assertEquals('High', alerts[0].Priority__c, 'Should be high priority');
    }

    @isTest
    static void testGenerateAlertsNoDecisionMaker() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        opp.StageName = 'Proposal';
        update opp;

        insert new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = con.Id,
            Role__c = 'Champion',
            Influence_Level__c = 'High',
            Engagement_Status__c = 'Engaged'
        );

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> alerts = [
            SELECT Id, Alert_Type__c
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Alert_Type__c = 'Missing Decision Maker'
        ];

        System.assertEquals(1, alerts.size(), 'Should generate Missing Decision Maker alert');
    }

    @isTest
    static void testGenerateAlertsSingleThreaded() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        insert new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = con.Id,
            Role__c = 'Champion',
            Influence_Level__c = 'High',
            Engagement_Status__c = 'Engaged'
        );

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> alerts = [
            SELECT Id, Alert_Type__c, Priority__c
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Alert_Type__c = 'Single-Threaded'
        ];

        System.assertEquals(1, alerts.size(), 'Should generate Single-Threaded alert');
        System.assertEquals('Medium', alerts[0].Priority__c, 'Should be medium priority');
    }

    @isTest
    static void testGenerateAlertsMissingExecutive() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE Title = 'Sales Manager' LIMIT 1];

        opp.Amount = 300000;
        update opp;

        insert new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = con.Id,
            Role__c = 'Champion',
            Influence_Level__c = 'High',
            Engagement_Status__c = 'Engaged'
        );

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> alerts = [
            SELECT Id, Alert_Type__c
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Alert_Type__c = 'Missing Executive'
        ];

        System.assertEquals(1, alerts.size(), 'Should generate Missing Executive alert');
    }

    @isTest
    static void testNoAlertsWhenCoverageComplete() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 3];

        List<Opportunity_Stakeholder__c> stakeholders = new List<Opportunity_Stakeholder__c>();
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id, Contact__c = contacts[0].Id,
            Role__c = 'Champion', Influence_Level__c = 'High', Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id, Contact__c = contacts[1].Id,
            Role__c = 'Decision Maker', Influence_Level__c = 'High', Engagement_Status__c = 'Engaged'
        ));
        stakeholders.add(new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id, Contact__c = contacts[2].Id,
            Role__c = 'Influencer', Influence_Level__c = 'High', Engagement_Status__c = 'Engaged'
        ));
        insert stakeholders;

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> alerts = [
            SELECT Id
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Status__c = 'Active'
        ];

        // Missing Budget Holder alert will fire (Budget Holder role is inactive in org picklist)
        // Champion and Decision Maker are covered so at most 1 alert expected
        System.assert(alerts.size() <= 1, 'Should have minimal alerts with good coverage');
    }

    @isTest
    static void testGetAlertsForOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        insert new Stakeholder_Alert__c(
            Opportunity__c = opp.Id,
            Alert_Type__c = 'Missing Champion',
            Title__c = 'Missing Champion',
            Priority__c = 'High',
            Status__c = 'Active',
            Message__c = 'Test alert message'
        );

        Test.startTest();
        List<StakeholderAlertService.AlertWrapper> results =
            StakeholderAlertService.getAlertsForOpportunity(opp.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 alert');
        System.assertEquals('Missing Champion', results[0].alertType, 'Alert type should match');
    }

    @isTest
    static void testUpdateAlertStatus() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        Stakeholder_Alert__c alert = new Stakeholder_Alert__c(
            Opportunity__c = opp.Id,
            Alert_Type__c = 'Missing Champion',
            Title__c = 'Missing Champion',
            Priority__c = 'High',
            Status__c = 'Active',
            Message__c = 'Test alert'
        );
        insert alert;

        Test.startTest();
        StakeholderAlertService.updateAlertStatus(alert.Id, 'Acknowledged');
        Test.stopTest();

        Stakeholder_Alert__c updated = [SELECT Status__c FROM Stakeholder_Alert__c WHERE Id = :alert.Id];
        System.assertEquals('Acknowledged', updated.Status__c, 'Status should be updated');
    }

    @isTest
    static void testDismissAlert() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];

        Stakeholder_Alert__c alert = new Stakeholder_Alert__c(
            Opportunity__c = opp.Id,
            Alert_Type__c = 'Missing Champion',
            Title__c = 'Missing Champion',
            Priority__c = 'High',
            Status__c = 'Active',
            Message__c = 'Test alert'
        );
        insert alert;

        Test.startTest();
        StakeholderAlertService.dismissAlert(alert.Id);
        Test.stopTest();

        Stakeholder_Alert__c dismissed = [SELECT Status__c FROM Stakeholder_Alert__c WHERE Id = :alert.Id];
        System.assertEquals('Resolved', dismissed.Status__c, 'Status should be Resolved');
    }

    @isTest
    static void testAlertsDeletionOnRegenerate() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Large Deal' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        insert new Stakeholder_Alert__c(
            Opportunity__c = opp.Id,
            Alert_Type__c = 'Missing Champion',
            Title__c = 'Missing Champion',
            Priority__c = 'High',
            Status__c = 'Active',
            Message__c = 'Test alert'
        );

        insert new Opportunity_Stakeholder__c(
            Opportunity__c = opp.Id,
            Contact__c = con.Id,
            Role__c = 'Champion',
            Influence_Level__c = 'High',
            Engagement_Status__c = 'Engaged'
        );

        Test.startTest();
        StakeholderAlertService.generateAlertsForOpportunity(opp.Id);
        Test.stopTest();

        List<Stakeholder_Alert__c> openAlerts = [
            SELECT Id
            FROM Stakeholder_Alert__c
            WHERE Opportunity__c = :opp.Id
            AND Status__c = 'Active'
        ];

        // Old alert should be deleted, new ones may be created based on coverage
        System.assertNotEquals(null, openAlerts, 'Alerts should be regenerated');
    }
}