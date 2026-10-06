/**
 * Test class for StakeholderMapController
 */
@isTest
private class StakeholderMapControllerTest {

    @testSetup
    static void setup() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create test contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                AccountId = testAccount.Id,
                Title = 'Test Title ' + i,
                Email = 'test' + i + '@example.com'
            ));
        }
        insert contacts;

        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 100000
        );
        insert testOpp;

        // Create stakeholder maps
        List<Stakeholder_Map__c> maps = new List<Stakeholder_Map__c>();
        for (Integer i = 0; i < 3; i++) {
            maps.add(new Stakeholder_Map__c(
                Account__c = testAccount.Id,
                Contact__c = contacts[i].Id,
                Role__c = 'Champion;Decision Maker',
                Relationship_Strength__c = 4,
                Sentiment__c = 'Positive',
                Engagement_Status__c = 'Active',
                Position_X__c = 100 * i,
                Position_Y__c = 100,
                Notes__c = 'Test notes ' + i
            ));
        }
        insert maps;

        // Create stakeholder relationships
        Stakeholder_Relationship__c rel = new Stakeholder_Relationship__c(
            Account__c = testAccount.Id,
            From_Contact__c = contacts[0].Id,
            To_Contact__c = contacts[1].Id,
            Relationship_Type__c = 'Reports To',
            Strength__c = 5,
            Line_Style__c = 'Solid',
            Notes__c = 'Reports to relationship'
        );
        insert rel;

        // Create opportunity stakeholders
        List<Opportunity_Stakeholder__c> oppStakeholders = new List<Opportunity_Stakeholder__c>();
        for (Integer i = 0; i < 3; i++) {
            oppStakeholders.add(new Opportunity_Stakeholder__c(
                Opportunity__c = testOpp.Id,
                Contact__c = contacts[i].Id,
                Role__c = 'Champion',
                Influence_Level__c = 'High',
                Engagement_Status__c = 'Engaged',
                Is_Primary__c = i == 0
            ));
        }
        insert oppStakeholders;
    }

    @isTest
    static void testGetStakeholderMaps() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<StakeholderMapController.StakeholderMapWrapper> results =
            StakeholderMapController.getStakeholderMaps(acc.Id);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Should return 3 stakeholder maps');
        System.assertNotEquals(null, results[0].contactName, 'Contact name should be populated');
    }

    @isTest
    static void testGetStakeholderRelationships() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<StakeholderMapController.StakeholderRelationshipWrapper> results =
            StakeholderMapController.getStakeholderRelationships(acc.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 relationship');
        System.assertEquals('Reports To', results[0].relationshipType, 'Relationship type should match');
    }

    @isTest
    static void testGetAccountContacts() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<StakeholderMapController.ContactWrapper> results =
            StakeholderMapController.getAccountContacts(acc.Id);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return 5 contacts');
    }

    @isTest
    static void testUpsertStakeholderMap() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // contacts[0-2] already have Stakeholder_Map__c records from @TestSetup.
        // Use contacts[3] or [4] (no existing map) to avoid a duplicate-key error
        // if the object has a unique constraint on Account__c + Contact__c.
        Contact con = [
            SELECT Id FROM Contact
            WHERE Id NOT IN (SELECT Contact__c FROM Stakeholder_Map__c WHERE Account__c = :acc.Id)
            LIMIT 1
        ];

        StakeholderMapController.StakeholderMapWrapper wrapper =
            new StakeholderMapController.StakeholderMapWrapper();
        wrapper.accountId = acc.Id;
        wrapper.contactId = con.Id;
        wrapper.roles = new List<String>{'Champion'};
        wrapper.relationshipStrength = 5;
        wrapper.sentiment = 'Positive';
        wrapper.engagementStatus = 'Active';
        wrapper.positionX = 200;
        wrapper.positionY = 200;

        Test.startTest();
        String mapId = StakeholderMapController.upsertStakeholderMap(
            JSON.serialize(wrapper)
        );
        Test.stopTest();

        System.assertNotEquals(null, mapId, 'Should return stakeholder map ID');

        Stakeholder_Map__c created = [SELECT Id, Position_X__c FROM Stakeholder_Map__c WHERE Id = :mapId];
        System.assertEquals(200, created.Position_X__c, 'Position should match');
    }

    @isTest
    static void testUpdateStakeholderPositions() {
        Stakeholder_Map__c stakeholderMap = [SELECT Id FROM Stakeholder_Map__c LIMIT 1];

        List<StakeholderMapController.PositionUpdate> updates =
            new List<StakeholderMapController.PositionUpdate>();

        StakeholderMapController.PositionUpdate update1 =
            new StakeholderMapController.PositionUpdate();
        update1.mapId = stakeholderMap.Id;
        update1.x = 500;
        update1.y = 600;
        updates.add(update1);

        Test.startTest();
        StakeholderMapController.updateStakeholderPositions(JSON.serialize(updates));
        Test.stopTest();

        Stakeholder_Map__c updated = [
            SELECT Position_X__c, Position_Y__c
            FROM Stakeholder_Map__c
            WHERE Id = :stakeholderMap.Id
        ];
        System.assertEquals(500, updated.Position_X__c, 'X position should be updated');
        System.assertEquals(600, updated.Position_Y__c, 'Y position should be updated');
    }

    @isTest
    static void testDeleteStakeholderMap() {
        Stakeholder_Map__c stakeholderMap = [SELECT Id FROM Stakeholder_Map__c LIMIT 1];

        Test.startTest();
        StakeholderMapController.deleteStakeholderMap(stakeholderMap.Id);
        Test.stopTest();

        List<Stakeholder_Map__c> deleted = [
            SELECT Id
            FROM Stakeholder_Map__c
            WHERE Id = :stakeholderMap.Id
        ];
        System.assertEquals(0, deleted.size(), 'Map should be deleted');
    }

    @isTest
    static void testUpsertStakeholderRelationship() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // contacts[0] → contacts[1] already have a Stakeholder_Relationship__c from @TestSetup.
        // Use contacts[2] and contacts[3] to avoid any duplicate-key or unique constraint errors.
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY LastName LIMIT 4];

        StakeholderMapController.StakeholderRelationshipWrapper wrapper =
            new StakeholderMapController.StakeholderRelationshipWrapper();
        wrapper.accountId = acc.Id;
        wrapper.fromContactId = contacts[2].Id;
        wrapper.toContactId = contacts[3].Id;
        wrapper.relationshipType = 'Influences';
        wrapper.strength = 4;
        wrapper.lineStyle = 'Dashed';

        Test.startTest();
        String relId = StakeholderMapController.upsertStakeholderRelationship(
            JSON.serialize(wrapper)
        );
        Test.stopTest();

        System.assertNotEquals(null, relId, 'Should return relationship ID');
    }

    @isTest
    static void testCreateContactAndMap() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String mapId = StakeholderMapController.createContactAndMap(
            acc.Id,
            'New',
            'Contact',
            'VP Sales',
            'newcontact@example.com',
            '555-1234'
        );
        Test.stopTest();

        System.assertNotEquals(null, mapId, 'Should return stakeholder map ID');

        List<Contact> newContacts = [
            SELECT Id, FirstName, LastName
            FROM Contact
            WHERE Email = 'newcontact@example.com'
        ];
        System.assertEquals(1, newContacts.size(), 'New contact should be created');
        System.assertEquals('New', newContacts[0].FirstName, 'First name should match');
    }

    @isTest
    static void testErrorHandling() {
        Test.startTest();
        try {
            StakeholderMapController.upsertStakeholderMap('invalid json');
            System.assert(false, 'Should throw exception');
        } catch (Exception e) {
            System.assert(true, 'Exception should be caught');
        }
        Test.stopTest();
    }
}