/**
 * Controller for managing stakeholder maps and org chart data
 */
public with sharing class StakeholderMapController {

    /**
     * Get all stakeholder maps for an account
     */
    @AuraEnabled(cacheable=true)
    public static List<StakeholderMapWrapper> getStakeholderMaps(Id accountId) {
        List<StakeholderMapWrapper> wrappers = new List<StakeholderMapWrapper>();

        List<Stakeholder_Map__c> maps = [
            SELECT Id, Account__c, Contact__c, Contact__r.Name, Contact__r.Title, Contact__r.Email,
                   Contact__r.Phone, Role__c, Relationship_Strength__c, Sentiment__c,
                   Engagement_Status__c, Position_X__c, Position_Y__c, Notes__c,
                   Last_Contacted__c
            FROM Stakeholder_Map__c
            WHERE Account__c = :accountId
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
        ];

        for (Stakeholder_Map__c sm : maps) {
            wrappers.add(new StakeholderMapWrapper(sm));
        }

        return wrappers;
    }

    /**
     * Get all relationships for an account
     */
    @AuraEnabled(cacheable=true)
    public static List<StakeholderRelationshipWrapper> getStakeholderRelationships(Id accountId) {
        List<StakeholderRelationshipWrapper> wrappers = new List<StakeholderRelationshipWrapper>();

        List<Stakeholder_Relationship__c> relationships = [
            SELECT Id, Account__c, From_Contact__c, From_Contact__r.Name, To_Contact__c,
                   To_Contact__r.Name, Relationship_Type__c, Strength__c,
                   Notes__c, Line_Style__c
            FROM Stakeholder_Relationship__c
            WHERE Account__c = :accountId
            WITH USER_MODE
        ];

        for (Stakeholder_Relationship__c sr : relationships) {
            wrappers.add(new StakeholderRelationshipWrapper(sr));
        }

        return wrappers;
    }

    /**
     * Create or update stakeholder map
     */
    @AuraEnabled
    public static String upsertStakeholderMap(String mapData) {
        try {
            StakeholderMapWrapper wrapper = (StakeholderMapWrapper) JSON.deserialize(
                mapData, StakeholderMapWrapper.class
            );

            Stakeholder_Map__c sm = wrapper.toStakeholderMap();
            if (sm.Id == null && !Stakeholder_Map__c.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create stakeholder map');
            }
            if (sm.Id != null && !Stakeholder_Map__c.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update stakeholder map');
            }
            if (sm.Id == null) {
                SObjectAccessDecision sdSm = Security.stripInaccessible(AccessType.CREATABLE, new List<Stakeholder_Map__c>{sm});
                insert sdSm.getRecords();
                sm = (Stakeholder_Map__c) sdSm.getRecords()[0];
            } else {
                SObjectAccessDecision sdSm = Security.stripInaccessible(AccessType.UPDATABLE, new List<Stakeholder_Map__c>{sm});
                update sdSm.getRecords();
            }

            // Update account last modified timestamp
            if (sm.Account__c != null) {
                if (!Account.sObjectType.getDescribe().isUpdateable()) {
                    throw new AuraHandledException('Insufficient privileges to update account');
                }
                Account acc = new Account(
                    Id = sm.Account__c,
                    Org_Chart_Last_Updated__c = System.now()
                );
                SObjectAccessDecision sdAcc = Security.stripInaccessible(AccessType.UPDATABLE, new List<Account>{acc});
                update sdAcc.getRecords();
            }

            return sm.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error upserting stakeholder map: ' + e.getMessage());
        }
    }

    /**
     * Create or update stakeholder relationship
     */
    @AuraEnabled
    public static String upsertStakeholderRelationship(String relationshipData) {
        try {
            StakeholderRelationshipWrapper wrapper = (StakeholderRelationshipWrapper) JSON.deserialize(
                relationshipData, StakeholderRelationshipWrapper.class
            );

            Stakeholder_Relationship__c sr = wrapper.toStakeholderRelationship();
            if (sr.Id == null && !Stakeholder_Relationship__c.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create stakeholder relationship');
            }
            if (sr.Id != null && !Stakeholder_Relationship__c.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update stakeholder relationship');
            }
            if (sr.Id == null) {
                SObjectAccessDecision sdSr = Security.stripInaccessible(AccessType.CREATABLE, new List<Stakeholder_Relationship__c>{sr});
                insert sdSr.getRecords();
                sr = (Stakeholder_Relationship__c) sdSr.getRecords()[0];
            } else {
                SObjectAccessDecision sdSr = Security.stripInaccessible(AccessType.UPDATABLE, new List<Stakeholder_Relationship__c>{sr});
                update sdSr.getRecords();
            }

            return sr.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error upserting relationship: ' + e.getMessage());
        }
    }

    /**
     * Delete stakeholder map
     */
    @AuraEnabled
    public static void deleteStakeholderMap(Id mapId) {
        try {
            if (!Stakeholder_Map__c.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete stakeholder map');
            }
            Database.delete(new Stakeholder_Map__c(Id = mapId), AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting stakeholder map: ' + e.getMessage());
        }
    }

    /**
     * Delete stakeholder relationship
     */
    @AuraEnabled
    public static void deleteStakeholderRelationship(Id relationshipId) {
        try {
            if (!Stakeholder_Relationship__c.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete stakeholder relationship');
            }
            Database.delete(new Stakeholder_Relationship__c(Id = relationshipId), AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting relationship: ' + e.getMessage());
        }
    }

    /**
     * Get contacts for an account (for adding to map)
     */
    @AuraEnabled(cacheable=true)
    public static List<ContactWrapper> getAccountContacts(Id accountId) {
        List<ContactWrapper> wrappers = new List<ContactWrapper>();

        List<Contact> contacts = [
            SELECT Id, Name, Title, Email, Phone, LastActivityDate
            FROM Contact
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY Name
        ];

        for (Contact c : contacts) {
            wrappers.add(new ContactWrapper(c));
        }

        return wrappers;
    }

    /**
     * Create new contact and add to stakeholder map
     */
    @AuraEnabled
    public static String createContactAndMap(Id accountId, String firstName, String lastName,
                                             String title, String email, String phone) {
        try {
            Contact c = new Contact(
                AccountId = accountId,
                FirstName = firstName,
                LastName = lastName,
                Title = title,
                Email = email,
                Phone = phone
            );
            if (!Contact.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create contact');
            }
            SObjectAccessDecision sdC = Security.stripInaccessible(AccessType.CREATABLE, new List<Contact>{c});
            insert sdC.getRecords();
            c = (Contact) sdC.getRecords()[0];

            if (!Stakeholder_Map__c.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create stakeholder map');
            }
            Stakeholder_Map__c sm = new Stakeholder_Map__c(
                Account__c = accountId,
                Contact__c = c.Id,
                Engagement_Status__c = 'New'
            );
            SObjectAccessDecision sdSm = Security.stripInaccessible(AccessType.CREATABLE, new List<Stakeholder_Map__c>{sm});
            insert sdSm.getRecords();
            sm = (Stakeholder_Map__c) sdSm.getRecords()[0];

            return sm.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating contact: ' + e.getMessage());
        }
    }

    /**
     * Batch update stakeholder map positions (for drag and drop)
     */
    @AuraEnabled
    public static void updateStakeholderPositions(String positionsJson) {
        try {
            List<PositionUpdate> updates = (List<PositionUpdate>) JSON.deserialize(
                positionsJson, List<PositionUpdate>.class
            );

            List<Stakeholder_Map__c> mapsToUpdate = new List<Stakeholder_Map__c>();

            for (PositionUpdate pu : updates) {
                mapsToUpdate.add(new Stakeholder_Map__c(
                    Id = pu.mapId,
                    Position_X__c = pu.x,
                    Position_Y__c = pu.y
                ));
            }

            if (!mapsToUpdate.isEmpty()) {
                if (!Stakeholder_Map__c.sObjectType.getDescribe().isUpdateable()) {
                    throw new AuraHandledException('Insufficient privileges to update stakeholder positions');
                }
                SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, mapsToUpdate);
                update sd.getRecords();
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error updating positions: ' + e.getMessage());
        }
    }

    // Wrapper classes
    public class StakeholderMapWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String accountId;
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactTitle;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String contactPhone;
        @AuraEnabled public List<String> roles;
        @AuraEnabled public Decimal relationshipStrength;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String engagementStatus;
        @AuraEnabled public Decimal positionX;
        @AuraEnabled public Decimal positionY;
        @AuraEnabled public String notes;
        @AuraEnabled public Date lastContacted;

        public StakeholderMapWrapper() {}

        public StakeholderMapWrapper(Stakeholder_Map__c sm) {
            this.id = sm.Id;
            this.accountId = sm.Account__c;
            this.contactId = sm.Contact__c;
            this.contactName = sm.Contact__r.Name;
            this.contactTitle = sm.Contact__r.Title;
            this.contactEmail = sm.Contact__r.Email;
            this.contactPhone = sm.Contact__r.Phone;
            this.roles = sm.Role__c != null ? sm.Role__c.split(';') : new List<String>();
            this.relationshipStrength = sm.Relationship_Strength__c;
            this.sentiment = sm.Sentiment__c;
            this.engagementStatus = sm.Engagement_Status__c;
            this.positionX = sm.Position_X__c;
            this.positionY = sm.Position_Y__c;
            this.notes = sm.Notes__c;
            this.lastContacted = sm.Last_Contacted__c;
        }

        public Stakeholder_Map__c toStakeholderMap() {
            Stakeholder_Map__c sm = new Stakeholder_Map__c();
            if (this.id != null) sm.Id = this.id;
            sm.Account__c = this.accountId;
            sm.Contact__c = this.contactId;
            sm.Role__c = this.roles != null ? String.join(this.roles, ';') : null;
            sm.Relationship_Strength__c = this.relationshipStrength;
            sm.Sentiment__c = this.sentiment;
            sm.Engagement_Status__c = this.engagementStatus;
            sm.Position_X__c = this.positionX;
            sm.Position_Y__c = this.positionY;
            sm.Notes__c = this.notes;
            sm.Last_Contacted__c = this.lastContacted;
            return sm;
        }
    }

    public class StakeholderRelationshipWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String accountId;
        @AuraEnabled public String fromContactId;
        @AuraEnabled public String fromContactName;
        @AuraEnabled public String toContactId;
        @AuraEnabled public String toContactName;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public Decimal strength;
        @AuraEnabled public String notes;
        @AuraEnabled public String lineStyle;

        public StakeholderRelationshipWrapper() {}

        public StakeholderRelationshipWrapper(Stakeholder_Relationship__c sr) {
            this.id = sr.Id;
            this.accountId = sr.Account__c;
            this.fromContactId = sr.From_Contact__c;
            this.fromContactName = sr.From_Contact__r.Name;
            this.toContactId = sr.To_Contact__c;
            this.toContactName = sr.To_Contact__r.Name;
            this.relationshipType = sr.Relationship_Type__c;
            this.strength = sr.Strength__c;
            this.notes = sr.Notes__c;
            this.lineStyle = sr.Line_Style__c;
        }

        public Stakeholder_Relationship__c toStakeholderRelationship() {
            Stakeholder_Relationship__c sr = new Stakeholder_Relationship__c();
            if (this.id != null) sr.Id = this.id;
            sr.Account__c = this.accountId;
            sr.From_Contact__c = this.fromContactId;
            sr.To_Contact__c = this.toContactId;
            sr.Relationship_Type__c = this.relationshipType;
            sr.Strength__c = this.strength;
            sr.Notes__c = this.notes;
            sr.Line_Style__c = this.lineStyle;
            return sr;
        }
    }

    public class ContactWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public Date lastActivityDate;

        public ContactWrapper(Contact c) {
            this.id = c.Id;
            this.name = c.Name;
            this.title = c.Title;
            this.email = c.Email;
            this.phone = c.Phone;
            this.lastActivityDate = c.LastActivityDate;
        }
    }

    public class PositionUpdate {
        @AuraEnabled public String mapId;
        @AuraEnabled public Decimal x;
        @AuraEnabled public Decimal y;
    }
}