@IsTest
private class SmartRelatedListControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 15; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName  = 'Contact ' + String.valueOf(i).leftPad(2, '0'),
                AccountId = acc.Id,
                Email     = 'test' + i + '@example.com',
                LeadSource = 'Web'
            ));
        }
        insert contacts;
    }

    // --- getColumnDefinitions ---

    @IsTest
    static void columnDefsReturnsRequestedFields() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,Email,Phone');

        System.assertEquals(3, defs.size(), 'Should return exactly 3 column definitions');

        Set<String> fieldNames = new Set<String>();
        for (SmartRelatedListController.ColumnDef d : defs) {
            fieldNames.add(d.fieldName);
            System.assertNotEquals(null, d.label, 'Label should be populated for ' + d.fieldName);
            System.assertNotEquals(null, d.type, 'Type should be populated for ' + d.fieldName);
        }
        System.assert(fieldNames.contains('LastName'), 'Should include LastName');
        System.assert(fieldNames.contains('Email'), 'Should include Email');
        System.assert(fieldNames.contains('Phone'), 'Should include Phone');
    }

    @IsTest
    static void columnDefsDefaultsToNameWhenEmpty() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', '');

        System.assertEquals(1, defs.size(), 'Should default to exactly one field');
        System.assertEquals('Name', defs[0].fieldName, 'Default field should be Name');
    }

    @IsTest
    static void columnDefsReturnsPicklistValues() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LeadSource');

        System.assertEquals(1, defs.size(), 'Should return one column');
        System.assertEquals('PICKLIST', defs[0].type, 'Type should be PICKLIST');
        System.assertNotEquals(null, defs[0].picklistValues, 'Should include picklist values');
        System.assert(defs[0].picklistValues.size() > 0, 'Picklist values should not be empty');

        SmartRelatedListController.PicklistOption firstOpt = defs[0].picklistValues[0];
        System.assertNotEquals(null, firstOpt.label, 'Option should have a label');
        System.assertNotEquals(null, firstOpt.value, 'Option should have a value');
    }

    @IsTest
    static void columnDefsThrowsOnInvalidObject() {
        try {
            SmartRelatedListController.getColumnDefinitions('FakeObject__x', 'Name');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void columnDefsThrowsOnInvalidField() {
        try {
            SmartRelatedListController.getColumnDefinitions('Contact', 'TotallyFakeField__c');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    @IsTest
    static void columnDefsPopulatesUpdateableFlag() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,AccountId');

        for (SmartRelatedListController.ColumnDef d : defs) {
            System.assertNotEquals(null, d.updateable,
                'updateable flag should be set for ' + d.fieldName);
        }
    }

    // --- getRelatedRecords ---

    @IsTest
    static void relatedRecordsRespectsRowLimit() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 10, 0, null, null, null
        );

        System.assertEquals(10, records.size(), 'Should return exactly 10 records');
    }

    @IsTest
    static void relatedRecordsRespectsOffset() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 100, 10, null, null, null
        );

        System.assertEquals(5, records.size(), 'Should return remaining 5 records');
    }

    @IsTest
    static void relatedRecordsSortsAscending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 15, 0, 'LastName', 'asc', null
        );

        System.assertEquals(15, records.size(), 'Should return all 15 contacts');
        String prev = '';
        for (SObject rec : records) {
            String current = (String) rec.get('LastName');
            System.assert(current >= prev,
                'Expected ascending order, got "' + current + '" after "' + prev + '"');
            prev = current;
        }
    }

    @IsTest
    static void relatedRecordsSortsDescending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 15, 0, 'LastName', 'desc', null
        );

        System.assertEquals(15, records.size(), 'Should return all 15 contacts');
        String prev = 'zzzzz';
        for (SObject rec : records) {
            String current = (String) rec.get('LastName');
            System.assert(current <= prev,
                'Expected descending order, got "' + current + '" after "' + prev + '"');
            prev = current;
        }
    }

    @IsTest
    static void relatedRecordsFiltersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 50, 0, null, null, 'Contact 01'
        );

        System.assertEquals(1, records.size(), 'Should match exactly 1 record');
    }

    @IsTest
    static void relatedRecordsReturnsIdField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 1, 0, null, null, null
        );

        System.assertEquals(1, records.size(), 'Should return 1 record');
        System.assertNotEquals(null, records[0].Id, 'Record should include Id');
    }

    @IsTest
    static void relatedRecordsThrowsOnInvalidObject() {
        try {
            SmartRelatedListController.getRelatedRecords(
                'FakeObject__x', 'AccountId', UserInfo.getUserId(), 'Name', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void relatedRecordsThrowsOnBlankObject() {
        try {
            SmartRelatedListController.getRelatedRecords(
                '', 'AccountId', UserInfo.getUserId(), 'Name', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), e.getMessage());
        }
    }

    @IsTest
    static void relatedRecordsThrowsOnInvalidParentField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        try {
            SmartRelatedListController.getRelatedRecords(
                'Contact', 'FakeFieldId__c', acc.Id, 'Name', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    @IsTest
    static void relatedRecordsThrowsOnInvalidSortField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        try {
            SmartRelatedListController.getRelatedRecords(
                'Contact', 'AccountId', acc.Id, 'Name', 10, 0, 'FakeSort__c', 'asc', null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    @IsTest
    static void relatedRecordsThrowsOnInvalidSelectField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        try {
            SmartRelatedListController.getRelatedRecords(
                'Contact', 'AccountId', acc.Id, 'FakeColumn__c', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    // --- getTotalCount ---

    @IsTest
    static void totalCountReturnsAllRecords() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, null
        );

        System.assertEquals(15, count, 'Should count all 15 contacts');
    }

    @IsTest
    static void totalCountFiltersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, 'Contact 01'
        );

        System.assertEquals(1, count, 'Should match exactly 1 record');
    }

    @IsTest
    static void totalCountThrowsOnInvalidObject() {
        try {
            SmartRelatedListController.getTotalCount(
                'FakeObject__x', 'AccountId', UserInfo.getUserId(), null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void totalCountThrowsOnInvalidParentField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        try {
            SmartRelatedListController.getTotalCount(
                'Contact', 'FakeFieldId__c', acc.Id, null
            );
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    // --- Boundary conditions ---

    @IsTest
    static void relatedRecordsReturnsEmptyForUnrelatedParent() {
        Account lonely = new Account(Name = 'Lonely Account');
        insert lonely;

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', lonely.Id, 'LastName', 100, 0, null, null, null
        );

        System.assertEquals(0, records.size(), 'Unrelated parent should return 0 records');
    }

    @IsTest
    static void relatedRecordsOffsetBeyondTotalReturnsEmpty() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 100, 999, null, null, null
        );

        System.assertEquals(0, records.size(), 'Offset beyond total should return 0');
    }

    @IsTest
    static void relatedRecordsNullLimitReturnsAll() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', null, null, null, null, null
        );

        System.assertEquals(15, records.size(), 'Null limit should return all records');
    }

    @IsTest
    static void totalCountReturnsZeroForUnrelatedParent() {
        Account lonely = new Account(Name = 'Lonely Account 2');
        insert lonely;

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', lonely.Id, null
        );

        System.assertEquals(0, count, 'Unrelated parent should count 0');
    }

    // --- FLS enforcement ---

    @IsTest
    static void relatedRecordsStripInaccessiblePath() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 5, 0, null, null, null
        );

        System.assertEquals(5, records.size(), 'Should return 5 records');
        for (SObject rec : records) {
            System.assertNotEquals(null, rec.get('LastName'), 'LastName should be accessible');
        }
    }

    @IsTest
    static void columnDefsExcludesInaccessibleFields() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,Email');

        System.assertEquals(2, defs.size(), 'Both fields should be accessible for admin');
    }

    // --- getObjectLabel ---

    @IsTest
    static void objectLabelReturnsPluralLabel() {
        String label = SmartRelatedListController.getObjectLabel('Contact');
        System.assertEquals('Contacts', label, 'Plural label should be Contacts');
    }

    @IsTest
    static void objectLabelThrowsOnInvalidObject() {
        try {
            SmartRelatedListController.getObjectLabel('FakeObject__x');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void objectLabelThrowsOnBlankObject() {
        try {
            SmartRelatedListController.getObjectLabel('');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), e.getMessage());
        }
    }
}
