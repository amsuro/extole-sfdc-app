@IsTest
private class ExtoleWebhookControllerTest {
    private static void setRequest(String body) {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestBody = Blob.valueOf(body);
    }

    private static Extole_Writeback_Cfg__c makeConfig(
        String eventName,
        String objectType,
        String mappingsJson
    ) {
        Extole_Writeback_Cfg__c config = new Extole_Writeback_Cfg__c();
        config.Name = 'Test Config';
        config.Event_Name__c = eventName;
        config.Object_Type__c = objectType;
        config.Status__c = 'ACTIVE';
        config.Field_Mappings__c = mappingsJson;
        insert config;
        return config;
    }

    @IsTest
    static void testInvalidJson() {
        setRequest('not json at all');
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('invalid_payload')
        );
    }

    @IsTest
    static void testMissingEventName() {
        setRequest('{"data":{"email":"test@example.com"}}');
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('missing_event_name')
        );
    }

    @IsTest
    static void testNoConfigSkipped() {
        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-001","data":{"email":"x@x.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('skipped')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    @IsTest
    static void testInactiveConfigSkipped() {
        Extole_Writeback_Cfg__c config = makeConfig(
            'reward_earned',
            'Contact',
            null
        );
        config.Status__c = 'INACTIVE';
        update config;

        Contact c = new Contact(
            LastName = 'Test',
            Email = 'inactive-rule@example.com'
        );
        insert c;

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-inactive-001","data":{"email":"inactive-rule@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('skipped')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    @IsTest
    static void testDuplicateEventId() {
        Extole_Writeback_Log__c prior = new Extole_Writeback_Log__c(
            Event_Id__c = 'dup-123',
            Event_Name__c = 'reward_earned',
            Status__c = 'SUCCESS',
            Received_At__c = System.now()
        );
        insert prior;

        setRequest(
            '{"event_name":"reward_earned","event_id":"dup-123","data":{"email":"x@x.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('duplicate')
        );
        System.assertEquals(1, [SELECT COUNT() FROM Extole_Writeback_Log__c]);
    }

    @IsTest
    static void testContactUpdateByEmail() {
        Contact c = new Contact(
            LastName = 'Tester',
            Email = 'tester@example.com'
        );
        insert c;
        makeConfig('reward_earned', 'Contact', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-c1","data":{"email":"tester@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString()
                .contains('"status":"ok"')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(c.Id, logs[0].Record_Id__c);
    }

    @IsTest
    static void testContactUpdateBySalesforceId() {
        Contact c = new Contact(LastName = 'SfidTest');
        insert c;
        makeConfig('reward_earned', 'Contact', null);

        String payload =
            '{"event_name":"reward_earned","event_id":"ev-c2","data":{"salesforce_id":"' +
            c.Id +
            '"}}';
        setRequest(payload);
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(c.Id, logs[0].Record_Id__c);
    }

    @IsTest
    static void testLeadUpdateByEmail() {
        Lead l = new Lead(
            LastName = 'LeadTest',
            Company = 'ACME',
            Email = 'lead@example.com'
        );
        insert l;
        makeConfig('reward_earned', 'Lead', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-l1","data":{"email":"lead@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c, Record_Id__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
        System.assertEquals(l.Id, logs[0].Record_Id__c);
    }

    @IsTest
    static void testNoRecordFound() {
        makeConfig('reward_earned', 'Contact', null);
        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-nr1","data":{"email":"nobody@nowhere.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('SKIPPED', logs[0].Status__c);
    }

    @IsTest
    static void testApplyMappings() {
        Contact c = new Contact(
            LastName = 'MapTest',
            Email = 'map@example.com'
        );
        insert c;
        makeConfig(
            'reward_earned',
            'Contact',
            '[{"extoleKey":"value","sfdcField":"Description"}]'
        );

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-m1","data":{"email":"map@example.com","value":"Gold"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        Contact updated = [SELECT Description FROM Contact WHERE Id = :c.Id];
        System.assertEquals('Gold', updated.Description);
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
    }

    @IsTest
    static void testApplyMappings_missingKey() {
        Contact c = new Contact(
            LastName = 'MapMiss',
            Email = 'miss@example.com'
        );
        insert c;
        makeConfig(
            'reward_earned',
            'Contact',
            '[{"extoleKey":"nonexistent_key","sfdcField":"Description"}]'
        );

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-m2","data":{"email":"miss@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals('SUCCESS', logs[0].Status__c);
    }

    @IsTest
    static void testApplyMappings_invalidJson() {
        String badMappings = 'NOT_VALID_JSON';
        try {
            Contact c = new Contact(LastName = 'MapBad');
            ExtoleWebhookController.applyMappings(
                c,
                badMappings,
                new Map<String, Object>{ 'k' => 'v' }
            );
            System.assert(false, 'Expected exception');
        } catch (ExtoleApiException e) {
            System.assert(
                e.getMessage().contains('Invalid field mappings JSON')
            );
        }
    }

    @IsTest
    static void testMultipleConfigs() {
        Contact c = new Contact(
            LastName = 'Multi',
            Email = 'multi@example.com'
        );
        Lead l = new Lead(
            LastName = 'Multi',
            Company = 'ACME',
            Email = 'multi@example.com'
        );
        insert c;
        insert l;
        makeConfig('reward_earned', 'Contact', null);
        makeConfig('reward_earned', 'Lead', null);

        setRequest(
            '{"event_name":"reward_earned","event_id":"ev-mu1","data":{"email":"multi@example.com"}}'
        );
        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assert(
            RestContext.response.responseBody.toString()
                .contains('"processed":2')
        );
        List<Extole_Writeback_Log__c> logs = [
            SELECT Status__c
            FROM Extole_Writeback_Log__c
        ];
        System.assertEquals(2, logs.size());
        for (Extole_Writeback_Log__c log : logs) {
            System.assertEquals('SUCCESS', log.Status__c);
        }
    }

    @IsTest
    static void testFindRecord_contactByEmail() {
        Contact c = new Contact(LastName = 'FR1', Email = 'fr1@example.com');
        insert c;
        SObject result = ExtoleWebhookController.findRecord(
            'Contact',
            'fr1@example.com',
            null
        );
        System.assertNotEquals(null, result);
        System.assertEquals(c.Id, (String) result.get('Id'));
    }

    @IsTest
    static void testFindRecord_leadByEmail() {
        Lead l = new Lead(
            LastName = 'FR2',
            Company = 'ACME',
            Email = 'fr2@example.com'
        );
        insert l;
        SObject result = ExtoleWebhookController.findRecord(
            'Lead',
            'fr2@example.com',
            null
        );
        System.assertNotEquals(null, result);
        System.assertEquals(l.Id, (String) result.get('Id'));
    }

    @IsTest
    static void testFindRecord_unknownType() {
        SObject result = ExtoleWebhookController.findRecord(
            'Account',
            'x@x.com',
            null
        );
        System.assertEquals(null, result);
    }

    // ── Create if not found ──────────────────────────────────────────────────

    @IsTest
    static void testCreateIfNotFoundCreatesLeadWithEmailAndFirstName() {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest(
            '{"event_name":"signed_up","data":{"email":"new.friend@example.com","first_name":"Nia"}}'
        );

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        Lead created = [
            SELECT FirstName, LastName, Company, Email
            FROM Lead
            WHERE Email = 'new.friend@example.com'
        ];
        System.assertEquals('Nia', created.FirstName);
        System.assertEquals('Unknown', created.LastName, 'Salesforce requires a Last Name');
        System.assertEquals(
            ExtolePersonAccounts.isEnabled() ? null : 'Unknown',
            created.Company,
            'Company is a placeholder, except where Person Accounts is on (blank so the lead converts to a Person Account)'
        );
        Extole_Writeback_Log__c log = [SELECT Status__c, Object_Type__c FROM Extole_Writeback_Log__c];
        System.assertEquals('CREATED', log.Status__c);
        System.assertEquals('Lead', log.Object_Type__c);
    }

    @IsTest
    static void testCreateIfNotFoundCreatesContact() {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Contact', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest(
            '{"event_name":"signed_up","data":{"email":"new.contact@example.com"}}'
        );

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Contact WHERE Email = 'new.contact@example.com']
        );
    }

    @IsTest
    static void testNoCreateWhenOptionIsOff() {
        makeConfig('signed_up', 'Lead', '[]');
        setRequest(
            '{"event_name":"signed_up","data":{"email":"not.created@example.com"}}'
        );

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead WHERE Email = 'not.created@example.com']
        );
        System.assertEquals(
            'SKIPPED',
            [SELECT Status__c FROM Extole_Writeback_Log__c][0].Status__c
        );
    }

    @IsTest
    static void testCreateIfNotFoundUpdatesExistingRecordInsteadOfCreating() {
        insert new Lead(LastName = 'Existing', Company = 'Acme', Email = 'existing.lead@example.com');
        Extole_Writeback_Cfg__c cfg = makeConfig(
            'signed_up',
            'Lead',
            '[{"extoleKey":"note","sfdcField":"Description"}]'
        );
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest(
            '{"event_name":"signed_up","data":{"email":"existing.lead@example.com","note":"hi"}}'
        );

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Lead WHERE Email = 'existing.lead@example.com']
        );
        System.assertEquals(
            'hi',
            [SELECT Description FROM Lead WHERE Email = 'existing.lead@example.com'].Description
        );
    }

    @IsTest
    static void testCreateUsesLastNameFromPayloadWhenSent() {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest(
            '{"event_name":"signed_up","data":{"email":"full.name@example.com","first_name":"Nia","last_name":"Named"}}'
        );

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        Lead l = [SELECT FirstName, LastName FROM Lead WHERE Email = 'full.name@example.com'];
        System.assertEquals('Nia', l.FirstName);
        System.assertEquals('Named', l.LastName);
    }

    // ── Person Accounts and duplicate prevention ─────────────────────────────
    // Person Account tests skip themselves in orgs where the feature is off.

    private static Id makePersonAccount(String email) {
        Id personRt = (Id) Database.query(
            'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true LIMIT 1'
        )[0].get('Id');
        SObject pa = Schema.getGlobalDescribe().get('Account').newSObject();
        pa.put('RecordTypeId', personRt);
        pa.put('FirstName', 'Pat');
        pa.put('LastName', 'Person');
        pa.put('PersonEmail', email);
        insert pa;
        return (Id) pa.get('Id');
    }

    @IsTest
    static void testFindRecordAccountMatchesPersonAccountByEmail() {
        if (!ExtolePersonAccounts.isEnabled()) return;
        Id accountId = makePersonAccount('person.account@example.com');

        SObject found = ExtoleWebhookController.findRecord('Account', 'person.account@example.com', null);

        System.assertNotEquals(null, found);
        System.assertEquals(accountId, (Id) found.get('Id'));
    }

    @IsTest
    static void testAccountRuleWritesToPersonAccount() {
        if (!ExtolePersonAccounts.isEnabled()) return;
        Id accountId = makePersonAccount('writeback.pa@example.com');
        makeConfig('pa_event', 'Account', '[{"extoleKey":"note","sfdcField":"Description"}]');
        setRequest('{"event_name":"pa_event","data":{"email":"writeback.pa@example.com","note":"via account rule"}}');

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        Account updated = (Account) Database.query(
            'SELECT Id, Description FROM Account WHERE Id = \'' + accountId + '\''
        )[0];
        System.assertEquals('via account rule', updated.Description);
    }

    @IsTest
    static void testAccountRuleNeverCreatesRecords() {
        if (!ExtolePersonAccounts.isEnabled()) return;
        Extole_Writeback_Cfg__c cfg = makeConfig('pa_event', 'Account', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest('{"event_name":"pa_event","data":{"email":"nobody@example.com"}}');

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals('SKIPPED', [SELECT Status__c FROM Extole_Writeback_Log__c][0].Status__c);
    }

    @IsTest
    static void testLeadCreateSkippedWhenPersonAccountExists() {
        if (!ExtolePersonAccounts.isEnabled()) return;
        makePersonAccount('already.person@example.com');
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest('{"event_name":"signed_up","data":{"email":"already.person@example.com"}}');

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Email = 'already.person@example.com']);
        Extole_Writeback_Log__c log = [SELECT Status__c, Error__c FROM Extole_Writeback_Log__c LIMIT 1];
        System.assertEquals('SKIPPED', log.Status__c);
        System.assert(log.Error__c.contains('already exists'));
    }

    @IsTest
    static void testCreatedLeadHasNoCompanyWhenPersonAccountsEnabled() {
        if (!ExtolePersonAccounts.isEnabled()) return;
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest('{"event_name":"signed_up","data":{"email":"no.company@example.com"}}');

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            null,
            [SELECT Company FROM Lead WHERE Email = 'no.company@example.com'][0].Company,
            'Company must stay blank so the lead converts to a Person Account'
        );
    }

    @IsTest
    static void testLeadCreateSkippedWhenContactExists() {
        insert new Contact(LastName = 'Existing', Email = 'existing.contact@example.com');
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        setRequest('{"event_name":"signed_up","data":{"email":"existing.contact@example.com"}}');

        Test.startTest();
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead WHERE Email = 'existing.contact@example.com'],
            'A Lead must not be created for an email that already has a Contact'
        );
    }

    @IsTest
    static void testRepeatedEventCreatesOnlyOneLead() {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;

        Test.startTest();
        for (Integer i = 0; i < 3; i++) {
            setRequest('{"event_name":"signed_up","data":{"email":"  Repeat@Example.com "}}');
            ExtoleWebhookController.doPost();
        }
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Lead WHERE Email = 'repeat@example.com'],
            'Repeated deliveries, even with different case or spacing, must not create duplicates'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Extole_Writeback_Lock__c],
            'Lock rows must not be left behind'
        );
    }

    @IsTest
    static void testBusyLockReturns503ForRetry() {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', '[]');
        cfg.Create_If_Not_Found__c = true;
        update cfg;
        insert new Extole_Writeback_Lock__c(Key__c = 'busy@example.com');

        Test.startTest();
        setRequest('{"event_name":"signed_up","data":{"email":"Busy@Example.com"}}');
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(503, RestContext.response.statusCode);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Lead WHERE Email = 'busy@example.com'],
            'A delivery that cannot take the lock must not create the record'
        );
    }

    // ─── One Lead per Extole program and campaign ─────────────────────────────

    private static void makeLeadCreateRule(String mappingsJson) {
        Extole_Writeback_Cfg__c cfg = makeConfig('signed_up', 'Lead', mappingsJson);
        cfg.Create_If_Not_Found__c = true;
        update cfg;
    }

    private static void sendSignUp(String email, String program, String campaign) {
        setRequest(
            '{"event_name":"signed_up","data":{"email":"' + email + '","program_name":"' + program +
            '","campaign_name":"' + campaign + '"}}'
        );
        ExtoleWebhookController.doPost();
    }

    @IsTest
    static void testCreatedLeadStoresProgramCampaignAndDefaultLeadSource() {
        makeLeadCreateRule('[]');

        Test.startTest();
        sendSignUp('maria@example.com', 'Refer a Friend', 'Spring 2025 Referral Bonus');
        Test.stopTest();

        Lead created = [
            SELECT Extole_Program_Name__c, Extole_Campaign_Name__c, LeadSource
            FROM Lead WHERE Email = 'maria@example.com'
        ];
        System.assertEquals('Refer a Friend', created.Extole_Program_Name__c);
        System.assertEquals('Spring 2025 Referral Bonus', created.Extole_Campaign_Name__c);
        System.assertEquals('Extole', created.LeadSource);
    }

    @IsTest
    static void testNewProgramAndCampaignGetsItsOwnLead() {
        makeLeadCreateRule('[]');

        Test.startTest();
        sendSignUp('maria@example.com', 'Refer a Friend', 'Spring 2025 Referral Bonus');
        sendSignUp('maria@example.com', 'Welcome Offer', 'Welcome Offer Spring Bonus');
        Test.stopTest();

        System.assertEquals(
            2, [SELECT COUNT() FROM Lead WHERE Email = 'maria@example.com'],
            'A new program and campaign for the same email gets its own Lead'
        );
        System.assertEquals(2, [SELECT COUNT() FROM Extole_Writeback_Log__c WHERE Status__c = 'CREATED']);
    }

    @IsTest
    static void testRepeatOfSameProgramAndCampaignCreatesNothing() {
        makeLeadCreateRule('[]');

        Test.startTest();
        sendSignUp('maria@example.com', 'Refer a Friend', 'Spring');
        sendSignUp('maria@example.com', 'Refer a Friend', 'Spring');
        Test.stopTest();

        System.assertEquals(
            1, [SELECT COUNT() FROM Lead WHERE Email = 'maria@example.com'],
            'An identical program and campaign must not create another Lead'
        );
    }

    @IsTest
    static void testLeadFromAnotherSourceDoesNotBlockAnExtoleLead() {
        insert new Lead(LastName = 'Web', Company = 'Acme', Email = 'maria@example.com', LeadSource = 'Web');
        makeLeadCreateRule('[]');

        Test.startTest();
        sendSignUp('maria@example.com', 'Refer a Friend', 'Spring');
        Test.stopTest();

        System.assertEquals(
            2, [SELECT COUNT() FROM Lead WHERE Email = 'maria@example.com'],
            'A Lead with no Extole program or campaign is not a duplicate'
        );
        System.assertEquals(
            1, [SELECT COUNT() FROM Lead WHERE Email = 'maria@example.com' AND LeadSource = 'Web'],
            'The existing Web Lead stays as it was'
        );
    }

    @IsTest
    static void testConvertedLeadCountsAsADuplicate() {
        Lead l = new Lead(
            LastName = 'Converted', Company = 'Acme', Email = 'converted@example.com',
            Extole_Program_Name__c = 'Refer a Friend', Extole_Campaign_Name__c = 'Spring'
        );
        insert l;
        Database.LeadConvert convert = new Database.LeadConvert();
        convert.setLeadId(l.Id);
        convert.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        convert.setDoNotCreateOpportunity(true);
        Database.convertLead(convert);
        makeLeadCreateRule('[]');

        Test.startTest();
        sendSignUp('converted@example.com', 'Refer a Friend', 'Spring');
        Test.stopTest();

        System.assertEquals(
            1, [SELECT COUNT() FROM Lead WHERE Email = 'converted@example.com'],
            'A converted Lead with the same program and campaign still counts as a duplicate'
        );
    }

    @IsTest
    static void testSalesforceIdDoesNotHideANewCampaign() {
        Lead first = new Lead(
            LastName = 'First', Company = 'Acme', Email = 'repeat.friend@example.com',
            Extole_Program_Name__c = 'Refer a Friend', Extole_Campaign_Name__c = 'Spring'
        );
        insert first;
        makeLeadCreateRule('[]');

        Test.startTest();
        setRequest(
            '{"event_name":"signed_up","data":{"email":"repeat.friend@example.com","salesforce_id":"' + first.Id +
            '","program_name":"Welcome Offer","campaign_name":"Welcome Spring"}}'
        );
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            2, [SELECT COUNT() FROM Lead WHERE Email = 'repeat.friend@example.com'],
            'The same person keeps one salesforce_id across campaigns, so it must not hide a new campaign'
        );
    }

    @IsTest
    static void testExplicitLeadSourceMappingWinsOverTheDefault() {
        makeLeadCreateRule('[{"extoleKey":"lead_source","sfdcField":"LeadSource"}]');

        Test.startTest();
        setRequest(
            '{"event_name":"signed_up","data":{"email":"maria@example.com","lead_source":"Partner Referral"}}'
        );
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals('Partner Referral', [SELECT LeadSource FROM Lead WHERE Email = 'maria@example.com'].LeadSource);
    }

    @IsTest
    static void testEventWithoutProgramOrCampaignStillMatchesByEmail() {
        insert new Lead(LastName = 'Existing', Company = 'Acme', Email = 'maria@example.com');
        makeLeadCreateRule('[]');

        Test.startTest();
        setRequest('{"event_name":"signed_up","data":{"email":"maria@example.com"}}');
        ExtoleWebhookController.doPost();
        Test.stopTest();

        System.assertEquals(
            1, [SELECT COUNT() FROM Lead WHERE Email = 'maria@example.com'],
            'Without program and campaign the rule behaves as before and finds the existing Lead by email'
        );
    }

    // ─── Campaign name lookup ─────────────────────────────────────────────────

    private class CampaignSummaryMock implements HttpCalloutMock {
        Integer status;
        String body;
        CampaignSummaryMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('/v2/campaign-summaries/'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }

    private static void sendSignUpWithCampaignId(String campaignNameJson) {
        setRequest(
            '{"event_name":"signed_up","data":{"email":"maria@example.com","program_name":"refer-a-friend",' +
            '"campaign_id":"7688479679926788624"' + campaignNameJson + '}}'
        );
        ExtoleWebhookController.doPost();
    }

    @IsTest
    static void testCampaignNameIsLookedUpFromTheCampaignId() {
        makeLeadCreateRule('[]');
        Test.setMock(
            HttpCalloutMock.class,
            new CampaignSummaryMock(200, '{"campaign_id":"7688479679926788624","campaign_name":"Refer a Friend - Salesforce CRM"}')
        );

        Test.startTest();
        sendSignUpWithCampaignId('');
        Test.stopTest();

        Lead created = [
            SELECT Extole_Program_Name__c, Extole_Campaign_Name__c FROM Lead WHERE Email = 'maria@example.com'
        ];
        System.assertEquals('refer-a-friend', created.Extole_Program_Name__c);
        System.assertEquals('Refer a Friend - Salesforce CRM', created.Extole_Campaign_Name__c);
    }

    @IsTest
    static void testCampaignIdIsStoredWhenTheLookupFails() {
        makeLeadCreateRule('[]');
        Test.setMock(HttpCalloutMock.class, new CampaignSummaryMock(404, '{}'));

        Test.startTest();
        sendSignUpWithCampaignId('');
        Test.stopTest();

        System.assertEquals(
            '7688479679926788624',
            [SELECT Extole_Campaign_Name__c FROM Lead WHERE Email = 'maria@example.com'].Extole_Campaign_Name__c,
            'The sign-up must not be lost when the name cannot be looked up'
        );
        Extole_Writeback_Log__c log = [SELECT Status__c, Error__c FROM Extole_Writeback_Log__c];
        System.assertEquals('CREATED', log.Status__c);
        System.assert(log.Error__c.contains('could not be looked up'));
    }

    @IsTest
    static void testNoLookupWhenTheCampaignNameIsAlreadySent() {
        makeLeadCreateRule('[]');
        // A failing mock would change the stored value if the lookup ran.
        Test.setMock(HttpCalloutMock.class, new CampaignSummaryMock(404, '{}'));

        Test.startTest();
        sendSignUpWithCampaignId(',"campaign_name":"Spring Bonus"');
        Test.stopTest();

        System.assertEquals(
            'Spring Bonus',
            [SELECT Extole_Campaign_Name__c FROM Lead WHERE Email = 'maria@example.com'].Extole_Campaign_Name__c
        );
    }
}
