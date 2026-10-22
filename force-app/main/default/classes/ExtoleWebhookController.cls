@RestResource(urlMapping='/extole/events')
global without sharing class ExtoleWebhookController {
    @HttpPost
    global static void doPost() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        String rawPayload = request.requestBody != null
            ? request.requestBody.toString()
            : '';

        String eventName;
        String eventId;
        String email;
        String salesforceId;
        Map<String, Object> data;

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                rawPayload
            );
            eventName = (String) body.get('event_name');
            eventId = (String) body.get('event_id');
            data = body.containsKey('data')
                ? (Map<String, Object>) body.get('data')
                : new Map<String, Object>();
            email = (String) data.get('email');
            if (email != null)
                email = email.trim();
            salesforceId = (String) data.get('salesforce_id');
        } catch (Exception e) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf('{"error":"invalid_payload"}');
            return;
        }

        if (String.isBlank(eventName)) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                '{"error":"missing_event_name"}'
            );
            return;
        }

        if (String.isNotBlank(eventId)) {
            List<Extole_Writeback_Log__c> prior = [
                SELECT Id
                FROM Extole_Writeback_Log__c
                WHERE Event_Id__c = :eventId AND Status__c != 'FAILED'
                LIMIT 1
            ];
            if (!prior.isEmpty()) {
                response.statusCode = 200;
                response.responseBody = Blob.valueOf('{"status":"duplicate"}');
                return;
            }
        }

        List<Extole_Writeback_Cfg__c> configs = [
            SELECT
                Id,
                Object_Type__c,
                Field_Mappings__c,
                Create_If_Not_Found__c
            FROM Extole_Writeback_Cfg__c
            WHERE Event_Name__c = :eventName AND Status__c = 'ACTIVE'
            LIMIT 50
        ];

        if (configs.isEmpty()) {
            safeWriteLog(
                eventName,
                eventId,
                email,
                salesforceId,
                null,
                null,
                'SKIPPED',
                'No active rule for: ' + eventName,
                rawPayload
            );
            response.statusCode = 200;
            response.responseBody = Blob.valueOf(
                '{"status":"skipped","reason":"no_config"}'
            );
            return;
        }

        // The campaign name is looked up before any DML: Salesforce does not allow a callout
        // after the lock insert in the same request.
        String campaignNameNote = resolveCampaignName(configs, data);

        Extole_Writeback_Lock__c lock;
        try {
            lock = acquireLock(email);
        } catch (Exception e) {
            // Another delivery for this person is still running. Ask Extole to retry rather
            // than risk a duplicate or silently drop the event.
            response.statusCode = 503;
            response.responseBody = Blob.valueOf('{"error":"busy_retry"}');
            return;
        }

        List<Extole_Writeback_Log__c> logs = new List<Extole_Writeback_Log__c>();

        for (Extole_Writeback_Cfg__c config : configs) {
            String objectType = config.Object_Type__c;
            String status = 'SUCCESS';
            String errDetail = null;
            String recordId = null;

            try {
                // Extole's Lead rules that create records also tell Leads apart by program and
                // campaign, so a person referred in two campaigns gets one Lead for each.
                String program = sourceValue(data, 'program_name');
                String campaign = sourceValue(data, 'campaign_name');
                Boolean tracksSource = config.Create_If_Not_Found__c == true
                    && objectType == 'Lead'
                    && (program != null || campaign != null);
                SObject record = tracksSource
                    ? findByExtoleSource(email, program, campaign)
                    : findRecord(objectType, email, salesforceId);
                Boolean canCreate = record == null
                    && config.Create_If_Not_Found__c
                    && String.isNotBlank(email)
                    && objectType != 'Account';
                if (canCreate && personAlreadyExists(email)) {
                    // Creating a Lead/Contact here would duplicate an existing person.
                    status = 'SKIPPED';
                    errDetail =
                        'A Contact or Person Account already exists for ' +
                        email +
                        '; set this rule\'s Object Type to Contact or Account instead of creating a ' +
                        objectType;
                } else if (canCreate) {
                    record = newRecord(objectType, email, data);
                    applyMappings(record, config.Field_Mappings__c, data);
                    if (tracksSource)
                        setExtoleSource(record, program, campaign);
                    errDetail = appendNote(
                        insertWithLeadSource(record, tracksSource),
                        campaignNameNote
                    );
                    recordId = (String) record.get('Id');
                    status = 'CREATED';
                } else if (record == null) {
                    status = 'SKIPPED';
                    errDetail =
                        'No matching ' +
                        objectType +
                        ' found — email=' +
                        email +
                        ' salesforceId=' +
                        salesforceId;
                } else {
                    recordId = (String) record.get('Id');
                    applyMappings(record, config.Field_Mappings__c, data);
                    update record;
                }
            } catch (Exception e) {
                status = 'FAILED';
                errDetail = e.getMessage();
            }

            logs.add(
                buildLog(
                    eventName,
                    eventId,
                    email,
                    salesforceId,
                    objectType,
                    recordId,
                    status,
                    errDetail,
                    rawPayload
                )
            );
        }
        releaseLock(lock);

        if (!logs.isEmpty()) {
            try {
                insert logs;
            } catch (Exception e) {
                System.debug(
                    'ExtoleWebhookController: log insert failed — ' +
                    e.getMessage()
                );
            }
        }

        response.statusCode = 200;
        response.responseBody = Blob.valueOf(
            '{"status":"ok","processed":' + logs.size() + '}'
        );
    }

    @TestVisible
    private static SObject findRecord(
        String objectType,
        String email,
        String salesforceId
    ) {
        if (objectType == 'Contact') {
            if (String.isNotBlank(salesforceId)) {
                List<Contact> r = [
                    SELECT Id
                    FROM Contact
                    WHERE Id = :salesforceId
                    LIMIT 1
                ];
                if (!r.isEmpty())
                    return r[0];
            }
            if (String.isNotBlank(email)) {
                List<Contact> r = [
                    SELECT Id
                    FROM Contact
                    WHERE Email = :email
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!r.isEmpty())
                    return r[0];
            }
        } else if (objectType == 'Account') {
            return findPersonAccount(email, salesforceId);
        } else if (objectType == 'Lead') {
            if (String.isNotBlank(salesforceId)) {
                List<Lead> r = [
                    SELECT Id
                    FROM Lead
                    WHERE Id = :salesforceId AND IsConverted = FALSE
                    LIMIT 1
                ];
                if (!r.isEmpty())
                    return r[0];
            }
            if (String.isNotBlank(email)) {
                List<Lead> r = [
                    SELECT Id
                    FROM Lead
                    WHERE Email = :email AND IsConverted = FALSE
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!r.isEmpty())
                    return r[0];
            }
        }
        return null;
    }

    // Extole sends campaign_id because the integration's script cannot read a campaign's name.
    // For a Lead rule that creates records, look the name up so the Lead stores something a
    // person can read. If the lookup fails the ID is stored instead, and the log says so.
    @TestVisible
    private static String resolveCampaignName(
        List<Extole_Writeback_Cfg__c> configs,
        Map<String, Object> data
    ) {
        if (sourceValue(data, 'campaign_name') != null)
            return null;
        String campaignId = sourceValue(data, 'campaign_id');
        if (campaignId == null)
            return null;
        Boolean needed = false;
        for (Extole_Writeback_Cfg__c config : configs) {
            if (config.Create_If_Not_Found__c == true && config.Object_Type__c == 'Lead')
                needed = true;
        }
        if (!needed)
            return null;
        String name = lookupCampaignName(campaignId);
        if (name == null) {
            data.put('campaign_name', campaignId);
            return 'The campaign name could not be looked up, so the campaign ID was stored';
        }
        data.put('campaign_name', name);
        return null;
    }

    @TestVisible
    private static String lookupCampaignName(String campaignId) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(
                'callout:Extole_API/v2/campaign-summaries/' +
                EncodingUtil.urlEncode(campaignId, 'UTF-8')
            );
            request.setMethod('GET');
            request.setTimeout(10000);
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() != 200)
                return null;
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                response.getBody()
            );
            Object name = body.containsKey('campaign_name')
                ? body.get('campaign_name')
                : body.get('name');
            return name == null || String.isBlank(String.valueOf(name))
                ? null
                : String.valueOf(name).trim();
        } catch (Exception e) {
            System.debug(
                'ExtoleWebhookController.lookupCampaignName: ' + e.getMessage()
            );
            return null;
        }
    }

    private static String appendNote(String existing, String note) {
        if (note == null)
            return existing;
        return existing == null ? note : existing + '; ' + note;
    }

    private static String sourceValue(Map<String, Object> data, String key) {
        Object value = data == null ? null : data.get(key);
        if (value == null || String.isBlank(String.valueOf(value)))
            return null;
        return String.valueOf(value).trim();
    }

    // Finds a Lead with the event's email and the same Extole program and campaign (whichever
    // the event sends). Converted Leads count, so a repeat event does not create a second Lead
    // after the first one converts. A Lead from another source has no Extole program or
    // campaign, so it never matches. salesforce_id is not used here: the same person keeps one
    // salesforce_id across campaigns, and it would point every later campaign at the first Lead.
    @TestVisible
    private static SObject findByExtoleSource(
        String email,
        String program,
        String campaign
    ) {
        if (String.isBlank(email))
            return null;
        String soql = 'SELECT Id FROM Lead WHERE Email = :email';
        Map<String, Object> binds = new Map<String, Object>{ 'email' => email };
        if (program != null) {
            soql += ' AND Extole_Program_Name__c = :program';
            binds.put('program', program);
        }
        if (campaign != null) {
            soql += ' AND Extole_Campaign_Name__c = :campaign';
            binds.put('campaign', campaign);
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 1';
        List<SObject> r = Database.queryWithBinds(
            soql,
            binds,
            AccessLevel.SYSTEM_MODE
        );
        return r.isEmpty() ? null : r[0];
    }

    private static void setExtoleSource(
        SObject record,
        String program,
        String campaign
    ) {
        if (program != null)
            record.put('Extole_Program_Name__c', program);
        if (campaign != null)
            record.put('Extole_Campaign_Name__c', campaign);
    }

    // Records the app creates get Lead Source "Extole" unless a mapping already set one. When the
    // org's Lead Source list does not allow "Extole", the record is created with no Lead Source
    // and the log says so, rather than losing the sign-up.
    // allowDuplicateAlerts: a Lead told apart by program and campaign may share an email with
    // another Lead, so Duplicate Rules set to "Allow with alert" must not stop the insert.
    // Rules set to "Block" still do.
    private static String insertWithLeadSource(
        SObject record,
        Boolean allowDuplicateAlerts
    ) {
        if (record.get('LeadSource') == null)
            record.put('LeadSource', 'Extole');
        try {
            insertRecord(record, allowDuplicateAlerts);
            return null;
        } catch (Exception e) {
            if (
                (String) record.get('LeadSource') != 'Extole' ||
                !e.getMessage().containsIgnoreCase('restricted picklist')
            ) {
                throw e;
            }
            record.put('LeadSource', null);
            insertRecord(record, allowDuplicateAlerts);
            return 'Created without a Lead Source: "Extole" is not an allowed Lead Source value in this org';
        }
    }

    private static void insertRecord(SObject record, Boolean allowDuplicateAlerts) {
        if (!allowDuplicateAlerts) {
            insert record;
            return;
        }
        Database.DMLOptions options = new Database.DMLOptions();
        options.duplicateRuleHeader.allowSave = true;
        Database.SaveResult result = Database.insert(record, options);
        if (!result.isSuccess()) {
            throw new DmlException(result.getErrors()[0].getMessage());
        }
    }

    // The unique Key__c makes a second insert for the same person wait until the first
    // transaction finishes, so the find-or-create is never run twice at once for one person.
    @TestVisible
    private static Extole_Writeback_Lock__c acquireLock(String email) {
        if (String.isBlank(email))
            return null;
        Extole_Writeback_Lock__c lock = new Extole_Writeback_Lock__c(
            Key__c = email.toLowerCase()
        );
        insert lock;
        return lock;
    }

    @TestVisible
    private static void releaseLock(Extole_Writeback_Lock__c lock) {
        if (lock != null)
            delete lock;
    }

    @TestVisible
    private static Boolean personAlreadyExists(String email) {
        if (String.isBlank(email))
            return false;
        // A Person Account's hidden contact is returned here too.
        return ![SELECT Id FROM Contact WHERE Email = :email LIMIT 1].isEmpty();
    }

    // PersonEmail and IsPersonAccount only exist when Person Accounts is enabled,
    // so these queries are dynamic and the class still compiles everywhere.
    @TestVisible
    private static SObject findPersonAccount(String email, String salesforceId) {
        if (!ExtolePersonAccounts.isEnabled())
            return null;
        if (String.isNotBlank(salesforceId)) {
            List<SObject> r = Database.query(
                'SELECT Id FROM Account WHERE Id = :salesforceId AND IsPersonAccount = true LIMIT 1'
            );
            if (!r.isEmpty())
                return r[0];
        }
        if (String.isNotBlank(email)) {
            List<SObject> r = Database.query(
                'SELECT Id FROM Account WHERE PersonEmail = :email AND IsPersonAccount = true ORDER BY CreatedDate DESC LIMIT 1'
            );
            if (!r.isEmpty())
                return r[0];
        }
        return null;
    }

    @TestVisible
    private static SObject newRecord(
        String objectType,
        String email,
        Map<String, Object> data
    ) {
        // Use the names the sign-up provides. Salesforce requires a Last Name (and a Company
        // on Leads), so anything missing gets an "Unknown" placeholder a rep can replace.
        String firstName = data == null ? null : (String) data.get('first_name');
        String lastName = data == null ? null : (String) data.get('last_name');
        if (String.isBlank(lastName))
            lastName = 'Unknown';
        if (objectType == 'Contact') {
            return new Contact(Email = email, FirstName = firstName, LastName = lastName);
        } else if (objectType == 'Lead') {
            Lead l = new Lead(Email = email, FirstName = firstName, LastName = lastName);
            // A Lead with a Company converts to a business Account. When Person Accounts is
            // on, leave Company blank so conversion produces a Person Account.
            if (!ExtolePersonAccounts.isEnabled())
                l.Company = 'Unknown';
            return l;
        }
        throw new ExtoleApiException(
            'Cannot create record for unsupported Object_Type__c: ' + objectType
        );
    }

    @TestVisible
    private static void applyMappings(
        SObject record,
        String mappingsJson,
        Map<String, Object> data
    ) {
        if (String.isBlank(mappingsJson))
            return;
        List<Object> mappings;
        try {
            mappings = (List<Object>) JSON.deserializeUntyped(mappingsJson);
        } catch (Exception e) {
            throw new ExtoleApiException(
                'Invalid field mappings JSON: ' + e.getMessage()
            );
        }
        for (Object m : mappings) {
            Map<String, Object> mapping = (Map<String, Object>) m;
            String extoleKey = (String) mapping.get('extoleKey');
            String sfdcField = (String) mapping.get('sfdcField');
            if (String.isBlank(extoleKey) || String.isBlank(sfdcField))
                continue;
            Object value = data.get(extoleKey);
            if (value == null)
                continue;
            try {
                record.put(sfdcField, String.valueOf(value));
            } catch (Exception e) {
                System.debug(
                    'ExtoleWebhookController: could not set ' +
                        sfdcField +
                        ': ' +
                        e.getMessage()
                );
            }
        }
    }

    private static Extole_Writeback_Log__c buildLog(
        String eventName,
        String eventId,
        String email,
        String salesforceId,
        String objectType,
        String recordId,
        String status,
        String error,
        String payload
    ) {
        Extole_Writeback_Log__c log = new Extole_Writeback_Log__c();
        log.Event_Name__c = eventName;
        log.Event_Id__c = eventId;
        log.Email__c = email;
        log.Salesforce_Id__c = salesforceId;
        log.Object_Type__c = objectType;
        log.Record_Id__c = recordId;
        log.Status__c = status;
        log.Error__c = error;
        log.Payload__c = payload != null &&
            payload.length() > 32768
            ? payload.substring(0, 32768)
            : payload;
        log.Received_At__c = System.now();
        return log;
    }

    private static void safeWriteLog(
        String eventName,
        String eventId,
        String email,
        String salesforceId,
        String objectType,
        String recordId,
        String status,
        String error,
        String payload
    ) {
        try {
            insert buildLog(
                eventName,
                eventId,
                email,
                salesforceId,
                objectType,
                recordId,
                status,
                error,
                payload
            );
        } catch (Exception e) {
            System.debug(
                'ExtoleWebhookController: safeWriteLog failed — ' +
                e.getMessage()
            );
        }
    }
}
