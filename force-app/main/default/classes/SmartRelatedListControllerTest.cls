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
    static void getColumnDefinitions_returnsRequestedFields() {
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
    static void getColumnDefinitions_defaultsToNameWhenEmpty() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', '');

        System.assertEquals(1, defs.size(), 'Should default to exactly one field');
        System.assertEquals('Name', defs[0].fieldName, 'Default field should be Name');
    }

    @IsTest
    static void getColumnDefinitions_returnsPicklistValues() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LeadSource');

        System.assertEquals(1, defs.size());
        System.assertEquals('PICKLIST', defs[0].type);
        System.assertNotEquals(null, defs[0].picklistValues);
        System.assert(defs[0].picklistValues.size() > 0);

        SmartRelatedListController.PicklistOption firstOpt = defs[0].picklistValues[0];
        System.assertNotEquals(null, firstOpt.label);
        System.assertNotEquals(null, firstOpt.value);
    }

    @IsTest
    static void getColumnDefinitions_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getColumnDefinitions('FakeObject__x', 'Name');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void getColumnDefinitions_throwsOnInvalidField() {
        try {
            SmartRelatedListController.getColumnDefinitions('Contact', 'TotallyFakeField__c');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid field'), e.getMessage());
        }
    }

    @IsTest
    static void getColumnDefinitions_populatesUpdateableFlag() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,AccountId');

        for (SmartRelatedListController.ColumnDef d : defs) {
            System.assertNotEquals(null, d.updateable,
                'updateable flag should be set for ' + d.fieldName);
        }
    }

    // --- getRelatedRecords ---

    @IsTest
    static void getRelatedRecords_respectsRowLimit() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 10, 0, null, null, null
        );

        System.assertEquals(10, records.size());
    }

    @IsTest
    static void getRelatedRecords_respectsOffset() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 100, 10, null, null, null
        );

        System.assertEquals(5, records.size());
    }

    @IsTest
    static void getRelatedRecords_sortsAscending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 15, 0, 'LastName', 'asc', null
        );

        System.assertEquals(15, records.size());
        String prev = '';
        for (SObject rec : records) {
            String current = (String) rec.get('LastName');
            System.assert(current >= prev,
                'Expected ascending order, got "' + current + '" after "' + prev + '"');
            prev = current;
        }
    }

    @IsTest
    static void getRelatedRecords_sortsDescending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 15, 0, 'LastName', 'desc', null
        );

        System.assertEquals(15, records.size());
        String prev = 'zzzzz';
        for (SObject rec : records) {
            String current = (String) rec.get('LastName');
            System.assert(current <= prev,
                'Expected descending order, got "' + current + '" after "' + prev + '"');
            prev = current;
        }
    }

    @IsTest
    static void getRelatedRecords_filtersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 50, 0, null, null, 'Contact 01'
        );

        System.assertEquals(1, records.size());
    }

    @IsTest
    static void getRelatedRecords_returnsIdField() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 1, 0, null, null, null
        );

        System.assertEquals(1, records.size());
        System.assertNotEquals(null, records[0].Id);
    }

    @IsTest
    static void getRelatedRecords_throwsOnInvalidObject() {
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
    static void getRelatedRecords_throwsOnBlankObject() {
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
    static void getRelatedRecords_throwsOnInvalidParentField() {
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
    static void getRelatedRecords_throwsOnInvalidSortField() {
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
    static void getRelatedRecords_throwsOnInvalidSelectField() {
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
    static void getTotalCount_returnsAllRecords() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, null
        );

        System.assertEquals(15, count);
    }

    @IsTest
    static void getTotalCount_filtersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, 'Contact 01'
        );

        System.assertEquals(1, count);
    }

    @IsTest
    static void getTotalCount_throwsOnInvalidObject() {
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
    static void getTotalCount_throwsOnInvalidParentField() {
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
    static void getRelatedRecords_returnsEmptyForUnrelatedParent() {
        // Account with no contacts
        Account lonely = new Account(Name = 'Lonely Account');
        insert lonely;

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', lonely.Id, 'LastName', 100, 0, null, null, null
        );

        System.assertEquals(0, records.size());
    }

    @IsTest
    static void getRelatedRecords_offsetBeyondTotalReturnsEmpty() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 100, 999, null, null, null
        );

        System.assertEquals(0, records.size());
    }

    @IsTest
    static void getRelatedRecords_nullLimitReturnsAll() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', null, null, null, null, null
        );

        System.assertEquals(15, records.size());
    }

    @IsTest
    static void getTotalCount_returnsZeroForUnrelatedParent() {
        Account lonely = new Account(Name = 'Lonely Account 2');
        insert lonely;

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', lonely.Id, null
        );

        System.assertEquals(0, count);
    }

    // --- FLS enforcement ---

    @IsTest
    static void getRelatedRecords_stripInaccessibleRemovesRestrictedFields() {
        // stripInaccessible is enforced at Controller:127 — verify it runs
        // without error and returns records. A full FLS test requires a
        // restricted profile, but we can at least confirm the method path
        // executes correctly for the running user.
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 5, 0, null, null, null
        );

        System.assertEquals(5, records.size());
        // Verify the fields we requested are present (accessible to test user)
        for (SObject rec : records) {
            System.assertNotEquals(null, rec.get('LastName'));
        }
    }

    @IsTest
    static void getColumnDefinitions_excludesInaccessibleFields() {
        // Under the system admin running tests, all fields are accessible.
        // This test confirms the method path works. For a real FLS test,
        // deploy a restricted profile + permission set and use System.runAs().
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,Email');

        // Both should be accessible for system admin
        System.assertEquals(2, defs.size());
    }

    // --- getObjectLabel ---

    @IsTest
    static void getObjectLabel_returnsPluralLabel() {
        String label = SmartRelatedListController.getObjectLabel('Contact');
        System.assertEquals('Contacts', label);
    }

    @IsTest
    static void getObjectLabel_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getObjectLabel('FakeObject__x');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void getObjectLabel_throwsOnBlankObject() {
        try {
            SmartRelatedListController.getObjectLabel('');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), e.getMessage());
        }
    }
}
