/**
 * @description Controller for Stakeholder 360 - Decision Intelligence for Salesforce
 * Provides methods for stakeholder management, relationship mapping, coverage analysis,
 * risk detection, and next best actions.
 */
public with sharing class Stakeholder360Controller {

    /**
     * @description Get all stakeholders for an Account with full details
     * @param accountId The Account Id
     * @return List of StakeholderWrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<StakeholderWrapper> getAccountStakeholders(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<StakeholderWrapper> stakeholders = new List<StakeholderWrapper>();

        try {
            List<Stakeholder__c> stakeholderRecords = [
                SELECT Id, Name, Contact__c, Contact__r.Name, Contact__r.Title,
                       Contact__r.Email, Contact__r.Phone, Contact__r.Department,
                       Account__c, Account__r.Name,
                       Role__c, Influence_Level__c, Decision_Power__c, Sentiment__c,
                       Engagement_Level__c, Notes__c, Priority_Score__c, Is_Primary_Stakeholder__c,
                       Last_Engagement_Date__c, Days_Since_Last_Engagement__c, Risk_Flag__c,
                       CreatedDate, LastModifiedDate
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY Priority_Score__c DESC, Role__c
            ];

            for (Stakeholder__c s : stakeholderRecords) {
                stakeholders.add(new StakeholderWrapper(s));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading stakeholders: ' + e.getMessage());
            throw new AuraHandledException('Unable to load stakeholders');
        }

        return stakeholders;
    }

    /**
     * @description Get all relationships for an Account
     * @param accountId The Account Id
     * @return List of RelationshipWrapper objects
     */
    @AuraEnabled
    public static List<RelationshipWrapper> getAccountRelationships(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<RelationshipWrapper> relationships = new List<RelationshipWrapper>();

        try {
            List<Stakeholder_Relationship__c> relationshipRecords = [
                SELECT Id, Name, From_Contact__c, From_Contact__r.Name,
                       To_Contact__c, To_Contact__r.Name, Account__c,
                       Relationship_Type__c, Strength__c, Direction__c,
                       Risk_Flag__c, Notes__c, CreatedDate
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY Relationship_Type__c
            ];

            for (Stakeholder_Relationship__c r : relationshipRecords) {
                relationships.add(new RelationshipWrapper(r));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading relationships: ' + e.getMessage());
            throw new AuraHandledException('Unable to load relationships');
        }

        return relationships;
    }

    /**
     * @description Calculate coverage analysis for an Account
     * @param accountId The Account Id
     * @return CoverageAnalysis object with coverage metrics
     */
    @AuraEnabled(cacheable=true)
    public static CoverageAnalysis getCoverageAnalysis(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        CoverageAnalysis analysis = new CoverageAnalysis();

        try {
            // Get all stakeholders for this account
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Role__c, Influence_Level__c, Decision_Power__c,
                       Sentiment__c, Engagement_Level__c, Is_Primary_Stakeholder__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            analysis.totalStakeholders = stakeholders.size();

            // Required roles for full coverage
            Set<String> requiredRoles = new Set<String>{
                'Decision Maker', 'Economic Buyer', 'Technical Buyer',
                'Champion', 'Influencer', 'User'
            };

            Set<String> coveredRoles = new Set<String>();

            for (Stakeholder__c s : stakeholders) {
                if (s.Role__c != null && requiredRoles.contains(s.Role__c)) {
                    coveredRoles.add(s.Role__c);
                }

                // Check specific roles
                if (s.Role__c == 'Decision Maker') analysis.hasDecisionMaker = true;
                if (s.Role__c == 'Economic Buyer') analysis.hasEconomicBuyer = true;
                if (s.Role__c == 'Technical Buyer') analysis.hasTechnicalBuyer = true;
                if (s.Role__c == 'Champion') analysis.hasChampion = true;
                if (s.Role__c == 'Influencer') analysis.hasInfluencer = true;
                if (s.Role__c == 'User') analysis.hasUser = true;
                if (s.Role__c == 'Blocker') analysis.hasBlocker = true;
            }

            analysis.coveredRoles = coveredRoles.size();
            analysis.requiredRoles = requiredRoles.size();
            analysis.coveragePercentage = requiredRoles.size() > 0
                ? (Decimal.valueOf(coveredRoles.size()) / Decimal.valueOf(requiredRoles.size()) * 100).setScale(0)
                : 0;

            // Determine coverage status
            if (analysis.coveragePercentage >= 80) {
                analysis.coverageStatus = 'Excellent';
            } else if (analysis.coveragePercentage >= 60) {
                analysis.coverageStatus = 'Good';
            } else if (analysis.coveragePercentage >= 40) {
                analysis.coverageStatus = 'Fair';
            } else {
                analysis.coverageStatus = 'Critical';
            }

            // Missing roles
            analysis.missingRoles = new List<String>();
            for (String role : requiredRoles) {
                if (!coveredRoles.contains(role)) {
                    analysis.missingRoles.add(role);
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error calculating coverage: ' + e.getMessage());
            throw new AuraHandledException('Unable to calculate coverage');
        }

        return analysis;
    }

    /**
     * @description Get risk signals for an Account
     * @param accountId The Account Id
     * @return List of RiskSignal objects
     */
    @AuraEnabled
    public static List<RiskSignal> getRiskSignals(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<RiskSignal> risks = new List<RiskSignal>();

        try {
            // Get stakeholders with potential risks
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Contact__r.Name, Role__c, Influence_Level__c,
                       Decision_Power__c, Sentiment__c, Engagement_Level__c,
                       Days_Since_Last_Engagement__c, Risk_Flag__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            // Get relationships with risks
            List<Stakeholder_Relationship__c> relationships = [
                SELECT Id, From_Contact__r.Name, To_Contact__r.Name,
                       Relationship_Type__c, Risk_Flag__c
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId AND Risk_Flag__c = true
                WITH SECURITY_ENFORCED
            ];

            // Check for risk signals
            Boolean hasChampion = false;
            Boolean hasDecisionMaker = false;
            Integer negativeInfluencers = 0;
            Integer coldStakeholders = 0;

            for (Stakeholder__c s : stakeholders) {
                if (s.Role__c == 'Champion' && s.Sentiment__c == 'Positive') hasChampion = true;
                if (s.Role__c == 'Decision Maker') hasDecisionMaker = true;

                // Blocker with high influence
                if (s.Role__c == 'Blocker' && s.Influence_Level__c == 'High') {
                    risks.add(new RiskSignal(
                        'High-Power Blocker',
                        s.Contact__r.Name + ' is a Blocker with High Influence',
                        'High',
                        'blocker'
                    ));
                }

                // Negative sentiment with decision power
                if (s.Sentiment__c == 'Negative' &&
                    (s.Decision_Power__c == 'High' || s.Influence_Level__c == 'High')) {
                    negativeInfluencers++;
                    risks.add(new RiskSignal(
                        'Negative Key Stakeholder',
                        s.Contact__r.Name + ' has negative sentiment with high influence/power',
                        'High',
                        'sentiment'
                    ));
                }

                // No engagement in 30+ days
                if (s.Days_Since_Last_Engagement__c != null && s.Days_Since_Last_Engagement__c > 30) {
                    coldStakeholders++;
                }
            }

            // No champion
            if (!hasChampion) {
                risks.add(new RiskSignal(
                    'Missing Champion',
                    'No identified Champion for this account',
                    'Medium',
                    'coverage'
                ));
            }

            // No decision maker
            if (!hasDecisionMaker) {
                risks.add(new RiskSignal(
                    'Missing Decision Maker',
                    'No identified Decision Maker for this account',
                    'High',
                    'coverage'
                ));
            }

            // Cold stakeholders
            if (coldStakeholders > 0) {
                risks.add(new RiskSignal(
                    'Stakeholder Engagement Gap',
                    coldStakeholders + ' stakeholder(s) with no engagement in 30+ days',
                    'Medium',
                    'engagement'
                ));
            }

            // Single-threaded (only 1-2 stakeholders)
            if (stakeholders.size() <= 2 && stakeholders.size() > 0) {
                risks.add(new RiskSignal(
                    'Single-Threaded Relationship',
                    'Only ' + stakeholders.size() + ' stakeholder(s) identified - expand coverage',
                    'High',
                    'coverage'
                ));
            }

            // Risky relationships
            for (Stakeholder_Relationship__c r : relationships) {
                if (r.Relationship_Type__c == 'Champion of Competitor') {
                    risks.add(new RiskSignal(
                        'Competitor Champion',
                        r.From_Contact__r.Name + ' champions a competitor',
                        'High',
                        'competitor'
                    ));
                }
                if (r.Relationship_Type__c == 'Political Opponent') {
                    risks.add(new RiskSignal(
                        'Political Opposition',
                        r.From_Contact__r.Name + ' has political opposition with ' + r.To_Contact__r.Name,
                        'Medium',
                        'political'
                    ));
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error detecting risks: ' + e.getMessage());
            throw new AuraHandledException('Unable to detect risks');
        }

        return risks;
    }

    /**
     * @description Get opportunity signals for an Account
     * @param accountId The Account Id
     * @return List of OpportunitySignal objects
     */
    @AuraEnabled
    public static List<OpportunitySignal> getOpportunitySignals(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<OpportunitySignal> opportunities = new List<OpportunitySignal>();

        try {
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Contact__r.Name, Role__c, Influence_Level__c,
                       Decision_Power__c, Sentiment__c, Engagement_Level__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            List<Stakeholder_Relationship__c> relationships = [
                SELECT Id, From_Contact__r.Name, To_Contact__r.Name,
                       Relationship_Type__c, Strength__c
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            Boolean hasStrongChampion = false;
            Integer positiveInfluencers = 0;
            Boolean hasExecutiveAccess = false;
            Integer multiThreaded = stakeholders.size();

            for (Stakeholder__c s : stakeholders) {
                // Strong champion
                if (s.Role__c == 'Champion' && s.Sentiment__c == 'Positive' &&
                    (s.Influence_Level__c == 'High' || s.Decision_Power__c == 'High')) {
                    hasStrongChampion = true;
                    opportunities.add(new OpportunitySignal(
                        'Strong Champion Identified',
                        s.Contact__r.Name + ' is a strong champion with influence',
                        'High'
                    ));
                }

                // Positive key stakeholders
                if (s.Sentiment__c == 'Positive' &&
                    (s.Influence_Level__c == 'High' || s.Decision_Power__c == 'High')) {
                    positiveInfluencers++;
                }

                // Executive sponsor
                if (s.Role__c == 'Executive Sponsor') {
                    hasExecutiveAccess = true;
                    opportunities.add(new OpportunitySignal(
                        'Executive Sponsorship',
                        s.Contact__r.Name + ' is an Executive Sponsor',
                        'High'
                    ));
                }
            }

            // Multi-threaded relationship
            if (multiThreaded >= 5) {
                opportunities.add(new OpportunitySignal(
                    'Multi-Threaded Engagement',
                    multiThreaded + ' stakeholders engaged - strong account presence',
                    'Medium'
                ));
            }

            // Positive influence chain
            if (positiveInfluencers >= 3) {
                opportunities.add(new OpportunitySignal(
                    'Positive Influence Chain',
                    positiveInfluencers + ' positive key stakeholders identified',
                    'High'
                ));
            }

            // Strong relationships
            for (Stakeholder_Relationship__c r : relationships) {
                if (r.Relationship_Type__c == 'Trusted Advisor' && r.Strength__c >= 4) {
                    opportunities.add(new OpportunitySignal(
                        'Trusted Advisor Relationship',
                        r.From_Contact__r.Name + ' is a Trusted Advisor to ' + r.To_Contact__r.Name,
                        'Medium'
                    ));
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error detecting opportunities: ' + e.getMessage());
            throw new AuraHandledException('Unable to detect opportunities');
        }

        return opportunities;
    }

    /**
     * @description Get next best actions for an Account
     * @param accountId The Account Id
     * @return List of NextBestAction objects
     */
    @AuraEnabled(cacheable=true)
    public static List<NextBestAction> getNextBestActions(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<NextBestAction> actions = new List<NextBestAction>();

        try {
            // Get coverage analysis
            CoverageAnalysis coverage = getCoverageAnalysis(accountId);

            // Get stakeholders
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Contact__r.Name, Role__c, Influence_Level__c,
                       Decision_Power__c, Sentiment__c, Engagement_Level__c,
                       Days_Since_Last_Engagement__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            // Get relationships
            List<Stakeholder_Relationship__c> relationships = [
                SELECT Id, From_Contact__r.Name, To_Contact__r.Name,
                       Relationship_Type__c
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            Integer priority = 1;

            // Missing champion
            if (!coverage.hasChampion) {
                actions.add(new NextBestAction(
                    priority++,
                    'Identify Champion',
                    'You have no Champion. Identify and nurture a potential champion within the organization.',
                    'coverage',
                    'High'
                ));
            }

            // Missing decision maker
            if (!coverage.hasDecisionMaker) {
                actions.add(new NextBestAction(
                    priority++,
                    'Connect with Decision Maker',
                    'No Decision Maker identified. Request introduction or find the key decision maker.',
                    'coverage',
                    'High'
                ));
            }

            // Missing economic buyer
            if (!coverage.hasEconomicBuyer) {
                actions.add(new NextBestAction(
                    priority++,
                    'Engage Economic Buyer',
                    'Engage with the Economic Buyer to discuss budget and ROI.',
                    'coverage',
                    'High'
                ));
            }

            // Check for blockers
            for (Stakeholder__c s : stakeholders) {
                // Blocker with high influence
                if (s.Role__c == 'Blocker' && s.Influence_Level__c == 'High') {
                    actions.add(new NextBestAction(
                        priority++,
                        'Address Blocker',
                        s.Contact__r.Name + ' is blocking progress. Plan executive alignment or find workaround.',
                        'risk',
                        'High'
                    ));
                }

                // Cold engagement
                if (s.Days_Since_Last_Engagement__c != null && s.Days_Since_Last_Engagement__c > 30) {
                    actions.add(new NextBestAction(
                        priority++,
                        'Re-engage ' + s.Contact__r.Name,
                        'No engagement in ' + s.Days_Since_Last_Engagement__c.intValue() + ' days. Schedule a meeting.',
                        'engagement',
                        'Medium'
                    ));
                }

                // Negative sentiment
                if (s.Sentiment__c == 'Negative' && s.Influence_Level__c != 'Low') {
                    actions.add(new NextBestAction(
                        priority++,
                        'Improve Sentiment',
                        s.Contact__r.Name + ' has negative sentiment. Understand concerns and address them.',
                        'sentiment',
                        'Medium'
                    ));
                }
            }

            // Low coverage
            if (coverage.coveragePercentage < 50) {
                actions.add(new NextBestAction(
                    priority++,
                    'Expand Coverage',
                    'Only ' + coverage.coveragePercentage.intValue() + '% role coverage. Map additional stakeholders.',
                    'coverage',
                    'Medium'
                ));
            }

            // Check for competitor champions
            for (Stakeholder_Relationship__c r : relationships) {
                if (r.Relationship_Type__c == 'Champion of Competitor') {
                    actions.add(new NextBestAction(
                        priority++,
                        'Counter Competitor Influence',
                        r.From_Contact__r.Name + ' champions a competitor. Prepare counter messaging.',
                        'competitor',
                        'High'
                    ));
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating actions: ' + e.getMessage());
            throw new AuraHandledException('Unable to generate actions');
        }

        return actions;
    }

    /**
     * @description Get stakeholder timeline/history for an Account
     * @param accountId The Account Id
     * @return List of TimelineEvent objects
     */
    @AuraEnabled(cacheable=true)
    public static List<TimelineEvent> getStakeholderTimeline(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        List<TimelineEvent> events = new List<TimelineEvent>();

        try {
            // Get stakeholder history (if history tracking is enabled)
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Name, Contact__r.Name, Role__c, Sentiment__c,
                       CreatedDate, LastModifiedDate
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 50
            ];

            // Get relationship history
            List<Stakeholder_Relationship__c> relationships = [
                SELECT Id, Name, From_Contact__r.Name, To_Contact__r.Name,
                       Relationship_Type__c, CreatedDate
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            // Create timeline events from stakeholders
            for (Stakeholder__c s : stakeholders) {
                events.add(new TimelineEvent(
                    s.CreatedDate,
                    'Stakeholder Added',
                    s.Contact__r.Name + ' added as ' + (s.Role__c != null ? s.Role__c : 'Stakeholder'),
                    'stakeholder',
                    s.Id
                ));
            }

            // Create timeline events from relationships
            for (Stakeholder_Relationship__c r : relationships) {
                events.add(new TimelineEvent(
                    r.CreatedDate,
                    'Relationship Created',
                    r.Relationship_Type__c + ' relationship: ' + r.From_Contact__r.Name + ' → ' + r.To_Contact__r.Name,
                    'relationship',
                    r.Id
                ));
            }

            // Sort by date descending
            events.sort();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading timeline: ' + e.getMessage());
            throw new AuraHandledException('Unable to load timeline');
        }

        return events;
    }

    /**
     * @description Create a new stakeholder
     * @param stakeholder The stakeholder record to create
     * @return The created stakeholder Id
     */
    @AuraEnabled
    public static Id createStakeholder(Stakeholder__c stakeholder) {
        // Input validation
        if (stakeholder == null) {
            throw new AuraHandledException('Stakeholder record is required');
        }

        try {
            // CRUD check before insert
            if (!Stakeholder__c.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create stakeholder');
            }

            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.CREATABLE, new List<Stakeholder__c>{stakeholder});
            insert sd.getRecords();
            stakeholder = (Stakeholder__c) sd.getRecords()[0];
            return stakeholder.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating stakeholder: ' + e.getMessage());
            throw new AuraHandledException('Unable to create stakeholder');
        }
    }

    /**
     * @description Update a stakeholder
     * @param stakeholder The stakeholder record to update
     */
    @AuraEnabled
    public static void updateStakeholder(Stakeholder__c stakeholder) {
        // Input validation
        if (stakeholder == null || stakeholder.Id == null) {
            throw new AuraHandledException('Stakeholder record with ID is required');
        }

        try {
            // CRUD check before update
            if (!Stakeholder__c.sObjectType.getDescribe().isUpdateable()) {
                throw new AuraHandledException('Insufficient privileges to update stakeholder');
            }

            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.UPDATABLE, new List<Stakeholder__c>{stakeholder});
            update sd.getRecords();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating stakeholder: ' + e.getMessage());
            throw new AuraHandledException('Unable to update stakeholder');
        }
    }

    /**
     * @description Create a new relationship
     * @param relationship The relationship record to create
     * @return The created relationship Id
     */
    @AuraEnabled
    public static Id createRelationship(Stakeholder_Relationship__c relationship) {
        // Input validation
        if (relationship == null) {
            throw new AuraHandledException('Relationship record is required');
        }

        try {
            // CRUD check before insert
            if (!Stakeholder_Relationship__c.sObjectType.getDescribe().isCreateable()) {
                throw new AuraHandledException('Insufficient privileges to create relationship');
            }

            SObjectAccessDecision sd = Security.stripInaccessible(AccessType.CREATABLE, new List<Stakeholder_Relationship__c>{relationship});
            insert sd.getRecords();
            relationship = (Stakeholder_Relationship__c) sd.getRecords()[0];
            return relationship.Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating relationship: ' + e.getMessage());
            throw new AuraHandledException('Unable to create relationship');
        }
    }

    /**
     * @description Delete a stakeholder
     * @param stakeholderId The stakeholder Id to delete
     */
    @AuraEnabled
    public static void deleteStakeholder(Id stakeholderId) {
        // Input validation
        if (stakeholderId == null) {
            throw new AuraHandledException('Stakeholder ID is required');
        }

        try {
            // CRUD check before delete
            if (!Stakeholder__c.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete stakeholder');
            }

            delete new Stakeholder__c(Id = stakeholderId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error deleting stakeholder: ' + e.getMessage());
            throw new AuraHandledException('Unable to delete stakeholder');
        }
    }

    /**
     * @description Delete a relationship
     * @param relationshipId The relationship Id to delete
     */
    @AuraEnabled
    public static void deleteRelationship(Id relationshipId) {
        // Input validation
        if (relationshipId == null) {
            throw new AuraHandledException('Relationship ID is required');
        }

        try {
            // CRUD check before delete
            if (!Stakeholder_Relationship__c.sObjectType.getDescribe().isDeletable()) {
                throw new AuraHandledException('Insufficient privileges to delete relationship');
            }

            delete new Stakeholder_Relationship__c(Id = relationshipId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error deleting relationship: ' + e.getMessage());
            throw new AuraHandledException('Unable to delete relationship');
        }
    }

    /**
     * @description Get stakeholder tree data for Account - contacts grouped by role with related opportunities
     * @param accountId The Account Id
     * @return StakeholderTreeData object with hierarchical structure
     */
    @AuraEnabled(cacheable=true)
    public static StakeholderTreeData getStakeholderTreeData(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        StakeholderTreeData treeData = new StakeholderTreeData();

        try {
            // Get account name
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1];
            treeData.accountId = acc.Id;
            treeData.accountName = acc.Name;

            // Get all contacts associated with this account
            Map<Id, ContactNode> contactMap = new Map<Id, ContactNode>();

            // Get contacts with their titles from Contact object
            List<Contact> contacts = [
                SELECT Id, Name, Title, Department, Email, Phone, Photo_URL__c
                FROM Contact
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
            ];

            for (Contact c : contacts) {
                ContactNode node = new ContactNode();
                node.contactId = c.Id;
                node.contactName = c.Name;
                node.title = c.Title;
                node.department = c.Department;
                node.email = c.Email;
                node.photoUrl = c.Photo_URL__c;
                node.opportunities = new List<OpportunityNode>();
                node.roles = new List<String>();
                contactMap.put(c.Id, node);
            }

            // Get stakeholder records to get roles
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Contact__c, Contact__r.Name, Contact__r.Title,
                       Role__c, Influence_Level__c, Sentiment__c, Risk_Flag__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY Contact__r.Name
            ];

            // Map to track unique opportunities per contact
            Map<Id, Set<Id>> contactOpportunities = new Map<Id, Set<Id>>();

            for (Stakeholder__c s : stakeholders) {
                if (s.Contact__c == null) continue;

                ContactNode node = contactMap.get(s.Contact__c);
                if (node == null) {
                    // Contact may not be directly linked to account, create node
                    node = new ContactNode();
                    node.contactId = s.Contact__c;
                    node.contactName = s.Contact__r?.Name;
                    node.title = s.Contact__r?.Title;
                    node.opportunities = new List<OpportunityNode>();
                    node.roles = new List<String>();
                    contactMap.put(s.Contact__c, node);
                }

                // Add role if not already added
                if (s.Role__c != null && !node.roles.contains(s.Role__c)) {
                    node.roles.add(s.Role__c);
                }

                // Track influence and sentiment
                if (s.Influence_Level__c == 'High') node.hasHighInfluence = true;
                if (s.Sentiment__c == 'Positive') node.hasPositiveSentiment = true;
                if (s.Sentiment__c == 'Negative') node.hasNegativeSentiment = true;
                if (s.Risk_Flag__c == true) node.hasRisk = true;
            }

            // Get opportunities for contacts using OpportunityContactRole
            List<OpportunityContactRole> oppContactRoles = [
                SELECT Id, ContactId, OpportunityId, Opportunity.Name,
                       Opportunity.StageName, Opportunity.Amount, Opportunity.CloseDate, Role
                FROM OpportunityContactRole
                WHERE Opportunity.AccountId = :accountId AND ContactId IN :contactMap.keySet()
                WITH SECURITY_ENFORCED
                ORDER BY Opportunity.CloseDate DESC
            ];

            for (OpportunityContactRole ocr : oppContactRoles) {
                ContactNode node = contactMap.get(ocr.ContactId);
                if (node != null) {
                    OpportunityNode oppNode = new OpportunityNode();
                    oppNode.opportunityId = ocr.OpportunityId;
                    oppNode.opportunityName = ocr.Opportunity.Name;
                    oppNode.stageName = ocr.Opportunity.StageName;
                    oppNode.amount = ocr.Opportunity.Amount;
                    oppNode.closeDate = ocr.Opportunity.CloseDate;
                    oppNode.role = ocr.Role;
                    node.opportunities.add(oppNode);
                }
            }

            // Categorize contacts by their primary role
            treeData.champions = new List<ContactNode>();
            treeData.decisionMakers = new List<ContactNode>();
            treeData.influencers = new List<ContactNode>();
            treeData.blockers = new List<ContactNode>();
            treeData.others = new List<ContactNode>();

            for (ContactNode node : contactMap.values()) {
                // Skip contacts with no stakeholder roles
                if (node.roles.isEmpty()) continue;

                // Determine primary category based on roles
                String primaryRole = determinePrimaryRole(node.roles);
                node.primaryRole = primaryRole;
                node.opportunityCount = node.opportunities.size();

                if (primaryRole == 'Champion' || primaryRole == 'Executive Sponsor') {
                    treeData.champions.add(node);
                } else if (primaryRole == 'Decision Maker' || primaryRole == 'Economic Buyer') {
                    treeData.decisionMakers.add(node);
                } else if (primaryRole == 'Influencer' || primaryRole == 'Technical Buyer') {
                    treeData.influencers.add(node);
                } else if (primaryRole == 'Blocker') {
                    treeData.blockers.add(node);
                } else {
                    treeData.others.add(node);
                }
            }

            // Calculate totals
            treeData.totalContacts = treeData.champions.size() + treeData.decisionMakers.size() +
                                     treeData.influencers.size() + treeData.blockers.size() +
                                     treeData.others.size();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading stakeholder tree: ' + e.getMessage());
            throw new AuraHandledException('Unable to load stakeholder tree');
        }

        return treeData;
    }

    /**
     * @description Determine primary role from list of roles
     */
    private static String determinePrimaryRole(List<String> roles) {
        // Priority order for roles
        List<String> rolePriority = new List<String>{
            'Executive Sponsor', 'Champion', 'Decision Maker', 'Economic Buyer',
            'Technical Buyer', 'Influencer', 'Blocker', 'User', 'Gatekeeper'
        };

        for (String priorityRole : rolePriority) {
            if (roles.contains(priorityRole)) {
                return priorityRole;
            }
        }

        return roles.isEmpty() ? 'Other' : roles[0];
    }

    /**
     * @description Get relationship graph data - Account with Contacts, Opportunities, and Cases
     * @param accountId The Account Id
     * @return RelationshipGraphData object with hierarchical structure
     */
    @AuraEnabled(cacheable=true)
    public static RelationshipGraphData getRelationshipGraphData(Id accountId) {
        // Input validation
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        RelationshipGraphData graphData = new RelationshipGraphData();

        try {
            // Get account details
            Account acc = [SELECT Id, Name, Industry, Type FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1];
            graphData.accountId = acc.Id;
            graphData.accountName = acc.Name;
            graphData.accountIndustry = acc.Industry;
            graphData.accountType = acc.Type;

            // Get all contacts for this account
            List<Contact> contacts = [
                SELECT Id, Name, Title, Email, Phone, Department
                FROM Contact
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY Name
            ];

            Map<Id, GraphContactNode> contactNodeMap = new Map<Id, GraphContactNode>();

            for (Contact c : contacts) {
                GraphContactNode node = new GraphContactNode();
                node.contactId = c.Id;
                node.contactName = c.Name;
                node.title = c.Title;
                node.email = c.Email;
                node.phone = c.Phone;
                node.department = c.Department;
                node.opportunities = new List<GraphOpportunityNode>();
                node.cases = new List<GraphCaseNode>();
                contactNodeMap.put(c.Id, node);
            }

            // Get stakeholder records to get roles
            List<Stakeholder__c> stakeholders = [
                SELECT Id, Contact__c, Role__c, Influence_Level__c, Sentiment__c, Risk_Flag__c
                FROM Stakeholder__c
                WHERE Account__c = :accountId AND Contact__c != null
                WITH SECURITY_ENFORCED
            ];

            for (Stakeholder__c s : stakeholders) {
                GraphContactNode node = contactNodeMap.get(s.Contact__c);
                if (node != null) {
                    if (s.Role__c != null && !node.roles.contains(s.Role__c)) {
                        node.roles.add(s.Role__c);
                    }
                    if (s.Influence_Level__c == 'High') node.hasHighInfluence = true;
                    if (s.Sentiment__c == 'Positive') node.hasPositiveSentiment = true;
                    if (s.Sentiment__c == 'Negative') node.hasNegativeSentiment = true;
                    if (s.Risk_Flag__c == true) node.hasRisk = true;
                }
            }

            // Get opportunities associated with contacts (through OpportunityContactRole)
            List<OpportunityContactRole> oppContactRoles = [
                SELECT Id, ContactId, Contact.Name, OpportunityId, Opportunity.Name,
                       Opportunity.StageName, Opportunity.Amount, Opportunity.CloseDate, Role
                FROM OpportunityContactRole
                WHERE Opportunity.AccountId = :accountId AND ContactId IN :contactNodeMap.keySet()
                WITH SECURITY_ENFORCED
                ORDER BY Opportunity.CloseDate DESC
            ];

            Map<String, Set<Id>> contactOppMap = new Map<String, Set<Id>>();

            for (OpportunityContactRole ocr : oppContactRoles) {
                String key = ocr.ContactId + '_' + ocr.OpportunityId;
                if (!contactOppMap.containsKey(key)) {
                    contactOppMap.put(key, new Set<Id>{ ocr.OpportunityId });

                    GraphContactNode node = contactNodeMap.get(ocr.ContactId);
                    if (node != null) {
                        GraphOpportunityNode oppNode = new GraphOpportunityNode();
                        oppNode.opportunityId = ocr.OpportunityId;
                        oppNode.opportunityName = ocr.Opportunity.Name;
                        oppNode.stageName = ocr.Opportunity.StageName;
                        oppNode.amount = ocr.Opportunity.Amount;
                        oppNode.closeDate = ocr.Opportunity.CloseDate;
                        oppNode.contactRole = ocr.Role;
                        node.opportunities.add(oppNode);
                    }
                }
            }

            // Get ALL opportunities for the account
            List<Opportunity> allOpps = [
                SELECT Id, Name, StageName, Amount, CloseDate
                FROM Opportunity
                WHERE AccountId = :accountId
                WITH SECURITY_ENFORCED
                ORDER BY CloseDate DESC
                LIMIT 200
            ];

            // Track which opportunities are already associated with contacts
            Set<Id> contactLinkedOppIds = new Set<Id>();
            for (Set<Id> oppIds : contactOppMap.values()) {
                contactLinkedOppIds.addAll(oppIds);
            }

            // Account-level opportunities (not linked to any contact)
            graphData.accountOpportunities = new List<GraphOpportunityNode>();
            for (Opportunity opp : allOpps) {
                if (!contactLinkedOppIds.contains(opp.Id)) {
                    GraphOpportunityNode oppNode = new GraphOpportunityNode();
                    oppNode.opportunityId = opp.Id;
                    oppNode.opportunityName = opp.Name;
                    oppNode.stageName = opp.StageName;
                    oppNode.amount = opp.Amount;
                    oppNode.closeDate = opp.CloseDate;
                    graphData.accountOpportunities.add(oppNode);
                }
            }

            // Get open cases for the account (exclude closed cases)
            List<Case> allCases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, ContactId, CreatedDate
                FROM Case
                WHERE AccountId = :accountId AND IsClosed = false
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];

            // Track which cases are already associated with contacts
            Set<Id> contactLinkedCaseIds = new Set<Id>();

            for (Case c : allCases) {
                if (c.ContactId != null && contactNodeMap.containsKey(c.ContactId)) {
                    // Add to contact
                    GraphContactNode node = contactNodeMap.get(c.ContactId);
                    GraphCaseNode caseNode = new GraphCaseNode();
                    caseNode.caseId = c.Id;
                    caseNode.caseNumber = c.CaseNumber;
                    caseNode.subject = c.Subject;
                    caseNode.status = c.Status;
                    caseNode.priority = c.Priority;
                    caseNode.createdDate = c.CreatedDate;
                    node.cases.add(caseNode);
                    contactLinkedCaseIds.add(c.Id);
                }
            }

            // Account-level cases (not linked to any contact)
            graphData.accountCases = new List<GraphCaseNode>();
            for (Case c : allCases) {
                if (!contactLinkedCaseIds.contains(c.Id)) {
                    GraphCaseNode caseNode = new GraphCaseNode();
                    caseNode.caseId = c.Id;
                    caseNode.caseNumber = c.CaseNumber;
                    caseNode.subject = c.Subject;
                    caseNode.status = c.Status;
                    caseNode.priority = c.Priority;
                    caseNode.createdDate = c.CreatedDate;
                    graphData.accountCases.add(caseNode);
                }
            }

            // Build final contact list
            graphData.contacts = contactNodeMap.values();

            // Calculate totals
            graphData.totalContacts = graphData.contacts.size();
            Integer totalOpps = graphData.accountOpportunities.size();
            Integer totalCases = graphData.accountCases.size();
            for (GraphContactNode node : graphData.contacts) {
                node.opportunityCount = node.opportunities.size();
                node.caseCount = node.cases.size();
                node.rolesDisplay = String.join(node.roles, ', ');
                totalOpps += node.opportunityCount;
                totalCases += node.caseCount;
            }
            graphData.totalOpportunities = totalOpps;
            graphData.totalCases = totalCases;

            // Get Stakeholder_Relationship__c records for the account
            List<Stakeholder_Relationship__c> rels = [
                SELECT From_Contact__c, From_Contact__r.Name,
                       To_Contact__c,   To_Contact__r.Name,
                       Relationship_Type__c, Strength__c, Direction__c
                FROM Stakeholder_Relationship__c
                WHERE Account__c = :accountId
                WITH SECURITY_ENFORCED
            ];

            graphData.relationships = new List<GraphRelationshipNode>();
            for (Stakeholder_Relationship__c r : rels) {
                GraphRelationshipNode rn   = new GraphRelationshipNode();
                rn.fromContactId           = r.From_Contact__c;
                rn.fromContactName         = r.From_Contact__r.Name;
                rn.toContactId             = r.To_Contact__c;
                rn.toContactName           = r.To_Contact__r.Name;
                rn.relationshipType        = r.Relationship_Type__c;
                rn.strength                = r.Strength__c != null ? r.Strength__c.intValue() : 0;
                rn.direction               = r.Direction__c;
                graphData.relationships.add(rn);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading relationship graph: ' + e.getMessage());
            throw new AuraHandledException('Unable to load relationship graph');
        }

        return graphData;
    }

    // ===== WRAPPER CLASSES =====

    public class StakeholderWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String department;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String role;
        @AuraEnabled public String influenceLevel;
        @AuraEnabled public String decisionPower;
        @AuraEnabled public String sentiment;
        @AuraEnabled public String engagementLevel;
        @AuraEnabled public String notes;
        @AuraEnabled public Decimal priorityScore;
        @AuraEnabled public Boolean isKeyStakeholder;
        @AuraEnabled public Date lastEngagementDate;
        @AuraEnabled public Decimal daysSinceLastEngagement;
        @AuraEnabled public Boolean riskFlag;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;

        public StakeholderWrapper(Stakeholder__c s) {
            this.id = s.Id;
            this.name = s.Name;
            this.contactId = s.Contact__c;
            this.contactName = s.Contact__r?.Name;
            this.title = s.Contact__r?.Title;
            this.email = s.Contact__r?.Email;
            this.phone = s.Contact__r?.Phone;
            this.department = s.Contact__r?.Department;
            this.accountId = s.Account__c;
            this.accountName = s.Account__r?.Name;
            this.role = s.Role__c;
            this.influenceLevel = s.Influence_Level__c;
            this.decisionPower = s.Decision_Power__c;
            this.sentiment = s.Sentiment__c;
            this.engagementLevel = s.Engagement_Level__c;
            this.notes = s.Notes__c;
            this.priorityScore = s.Priority_Score__c;
            this.isKeyStakeholder = s.Is_Primary_Stakeholder__c;
            this.lastEngagementDate = s.Last_Engagement_Date__c;
            this.daysSinceLastEngagement = s.Days_Since_Last_Engagement__c;
            this.riskFlag = s.Risk_Flag__c;
            this.createdDate = s.CreatedDate;
            this.lastModifiedDate = s.LastModifiedDate;
        }
    }

    public class RelationshipWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id fromContactId;
        @AuraEnabled public String fromContactName;
        @AuraEnabled public Id toContactId;
        @AuraEnabled public String toContactName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public Decimal strength;
        @AuraEnabled public String direction;
        @AuraEnabled public Boolean riskFlag;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime createdDate;

        public RelationshipWrapper(Stakeholder_Relationship__c r) {
            this.id = r.Id;
            this.name = r.Name;
            this.fromContactId = r.From_Contact__c;
            this.fromContactName = r.From_Contact__r?.Name;
            this.toContactId = r.To_Contact__c;
            this.toContactName = r.To_Contact__r?.Name;
            this.accountId = r.Account__c;
            this.relationshipType = r.Relationship_Type__c;
            this.strength = r.Strength__c;
            this.direction = r.Direction__c;
            this.riskFlag = r.Risk_Flag__c;
            this.notes = r.Notes__c;
            this.createdDate = r.CreatedDate;
        }
    }

    public class CoverageAnalysis {
        @AuraEnabled public Integer totalStakeholders = 0;
        @AuraEnabled public Integer coveredRoles = 0;
        @AuraEnabled public Integer requiredRoles = 0;
        @AuraEnabled public Decimal coveragePercentage = 0;
        @AuraEnabled public String coverageStatus;
        @AuraEnabled public Boolean hasDecisionMaker = false;
        @AuraEnabled public Boolean hasEconomicBuyer = false;
        @AuraEnabled public Boolean hasTechnicalBuyer = false;
        @AuraEnabled public Boolean hasChampion = false;
        @AuraEnabled public Boolean hasInfluencer = false;
        @AuraEnabled public Boolean hasUser = false;
        @AuraEnabled public Boolean hasBlocker = false;
        @AuraEnabled public List<String> missingRoles;
    }

    public class RiskSignal {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String severity;
        @AuraEnabled public String category;

        public RiskSignal(String title, String description, String severity, String category) {
            this.title = title;
            this.description = description;
            this.severity = severity;
            this.category = category;
        }
    }

    public class OpportunitySignal {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String impact;

        public OpportunitySignal(String title, String description, String impact) {
            this.title = title;
            this.description = description;
            this.impact = impact;
        }
    }

    public class NextBestAction {
        @AuraEnabled public Integer priority;
        @AuraEnabled public String action;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public String urgency;

        public NextBestAction(Integer priority, String action, String description, String category, String urgency) {
            this.priority = priority;
            this.action = action;
            this.description = description;
            this.category = category;
            this.urgency = urgency;
        }
    }

    public class TimelineEvent implements Comparable {
        @AuraEnabled public Datetime eventDate;
        @AuraEnabled public String eventType;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public Id recordId;

        public TimelineEvent(Datetime eventDate, String eventType, String description, String category, Id recordId) {
            this.eventDate = eventDate;
            this.eventType = eventType;
            this.description = description;
            this.category = category;
            this.recordId = recordId;
        }

        public Integer compareTo(Object other) {
            TimelineEvent otherEvent = (TimelineEvent)other;
            if (this.eventDate > otherEvent.eventDate) return -1;
            if (this.eventDate < otherEvent.eventDate) return 1;
            return 0;
        }
    }

    public class StakeholderTreeData {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer totalContacts = 0;
        @AuraEnabled public List<ContactNode> champions;
        @AuraEnabled public List<ContactNode> decisionMakers;
        @AuraEnabled public List<ContactNode> influencers;
        @AuraEnabled public List<ContactNode> blockers;
        @AuraEnabled public List<ContactNode> others;
    }

    public class ContactNode {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
        @AuraEnabled public String email;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public String primaryRole;
        @AuraEnabled public List<String> roles;
        @AuraEnabled public List<OpportunityNode> opportunities;
        @AuraEnabled public Integer opportunityCount = 0;
        @AuraEnabled public Boolean hasHighInfluence = false;
        @AuraEnabled public Boolean hasPositiveSentiment = false;
        @AuraEnabled public Boolean hasNegativeSentiment = false;
        @AuraEnabled public Boolean hasRisk = false;
    }

    public class OpportunityNode {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String role;
    }

    public class RelationshipGraphData {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountIndustry;
        @AuraEnabled public String accountType;
        @AuraEnabled public Integer totalContacts = 0;
        @AuraEnabled public Integer totalOpportunities = 0;
        @AuraEnabled public Integer totalCases = 0;
        @AuraEnabled public List<GraphContactNode> contacts;
        @AuraEnabled public List<GraphOpportunityNode> accountOpportunities;
        @AuraEnabled public List<GraphCaseNode> accountCases;
        @AuraEnabled public List<GraphRelationshipNode> relationships;
    }

    public class GraphContactNode {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String title;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String department;
        @AuraEnabled public List<String> roles = new List<String>();
        @AuraEnabled public String rolesDisplay;
        @AuraEnabled public List<GraphOpportunityNode> opportunities;
        @AuraEnabled public List<GraphCaseNode> cases;
        @AuraEnabled public Integer opportunityCount = 0;
        @AuraEnabled public Integer caseCount = 0;
        @AuraEnabled public Boolean hasHighInfluence = false;
        @AuraEnabled public Boolean hasPositiveSentiment = false;
        @AuraEnabled public Boolean hasNegativeSentiment = false;
        @AuraEnabled public Boolean hasRisk = false;
    }

    public class GraphOpportunityNode {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String contactRole;
    }

    public class GraphCaseNode {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Datetime createdDate;
    }

    public class GraphRelationshipNode {
        @AuraEnabled public Id     fromContactId;
        @AuraEnabled public String fromContactName;
        @AuraEnabled public Id     toContactId;
        @AuraEnabled public String toContactName;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public Integer strength;
        @AuraEnabled public String direction;
    }
}