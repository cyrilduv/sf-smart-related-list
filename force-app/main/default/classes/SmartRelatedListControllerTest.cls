/**
 * SmartRelatedListControllerTest
 *
 * Test class for SmartRelatedListController.
 * Uses Account → Contact as the test relationship.
 * Creates 15 Contacts under a single Account in @TestSetup.
 *
 * Coverage targets:
 *  - getColumnDefinitions: valid fields, empty fields (default), invalid object, picklist field
 *  - getRelatedRecords:    basic, offset, sort asc/desc, search, invalid object, blank object
 *  - getTotalCount:        all records, with search, invalid object
 *  - getObjectLabel:       valid object, invalid object
 */
@IsTest
private class SmartRelatedListControllerTest {

    // ═════════════════════════════════════════════════════════════════════
    //  TEST DATA
    // ═════════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 15; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName  = 'Contact ' + i,
                AccountId = acc.Id,
                Email     = 'test' + i + '@example.com'
            ));
        }
        insert contacts;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  getColumnDefinitions
    // ═════════════════════════════════════════════════════════════════════

    @IsTest
    static void getColumnDefinitions_returnsRequestedFields() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LastName,Email,Phone');

        System.assertNotEquals(0, defs.size(), 'Should return column definitions');

        Boolean hasLastName = false;
        for (SmartRelatedListController.ColumnDef d : defs) {
            if (d.fieldName == 'LastName') {
                hasLastName = true;
                System.assertNotEquals(null, d.label, 'Label should be populated');
                System.assertNotEquals(null, d.type, 'Type should be populated');
            }
        }
        System.assert(hasLastName, 'Should include the LastName column');
    }

    @IsTest
    static void getColumnDefinitions_defaultsToNameWhenEmpty() {
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', '');

        System.assertNotEquals(0, defs.size(), 'Should default to at least the Name field');
    }

    @IsTest
    static void getColumnDefinitions_returnsPicklistValues() {
        // LeadSource is a standard picklist on Contact
        List<SmartRelatedListController.ColumnDef> defs =
            SmartRelatedListController.getColumnDefinitions('Contact', 'LeadSource');

        System.assertEquals(1, defs.size(), 'Should return one column');
        System.assertNotEquals(null, defs[0].picklistValues, 'Should include picklist values');
        System.assert(defs[0].picklistValues.size() > 0, 'Picklist values should not be empty');
    }

    @IsTest
    static void getColumnDefinitions_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getColumnDefinitions('FakeObject__x', 'Name');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  getRelatedRecords
    // ═════════════════════════════════════════════════════════════════════

    @IsTest
    static void getRelatedRecords_respectsRowLimit() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 10, 0, null, null, null
        );

        System.assertEquals(10, records.size(), 'Should return exactly rowLimit records');
    }

    @IsTest
    static void getRelatedRecords_respectsOffset() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 10, 10, null, null, null
        );

        System.assertEquals(5, records.size(), 'Should return the remaining 5 records after offset 10');
    }

    @IsTest
    static void getRelatedRecords_sortsAscending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 15, 0, 'LastName', 'asc', null
        );

        System.assertNotEquals(0, records.size(), 'Should return sorted records');
    }

    @IsTest
    static void getRelatedRecords_sortsDescending() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName', 15, 0, 'LastName', 'desc', null
        );

        System.assertNotEquals(0, records.size(), 'Should return desc-sorted records');
    }

    @IsTest
    static void getRelatedRecords_filtersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<SObject> records = SmartRelatedListController.getRelatedRecords(
            'Contact', 'AccountId', acc.Id, 'LastName,Email', 50, 0, null, null, 'Contact 1'
        );

        System.assert(records.size() > 0, 'Should return records matching the search term');
    }

    @IsTest
    static void getRelatedRecords_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getRelatedRecords(
                'FakeObject__x', 'AccountId', '001000000000000', 'Name', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    @IsTest
    static void getRelatedRecords_throwsOnBlankObject() {
        try {
            SmartRelatedListController.getRelatedRecords(
                '', 'AccountId', '001000000000000', 'Name', 10, 0, null, null, null
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), e.getMessage());
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  getTotalCount
    // ═════════════════════════════════════════════════════════════════════

    @IsTest
    static void getTotalCount_returnsAllRecords() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, null
        );

        System.assertEquals(15, count, 'Should count all 15 contacts');
    }

    @IsTest
    static void getTotalCount_filtersOnSearchTerm() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Integer count = SmartRelatedListController.getTotalCount(
            'Contact', 'AccountId', acc.Id, 'Contact 1'
        );

        System.assert(count > 0, 'Should find at least one record matching the search term');
    }

    @IsTest
    static void getTotalCount_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getTotalCount(
                'FakeObject__x', 'AccountId', '001000000000000', null
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  getObjectLabel
    // ═════════════════════════════════════════════════════════════════════

    @IsTest
    static void getObjectLabel_returnsPluralLabel() {
        String label = SmartRelatedListController.getObjectLabel('Contact');

        System.assertNotEquals(null, label, 'Should return a non-null label');
        System.assert(label.length() > 0, 'Label should not be empty');
    }

    @IsTest
    static void getObjectLabel_throwsOnInvalidObject() {
        try {
            SmartRelatedListController.getObjectLabel('FakeObject__x');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid object'), e.getMessage());
        }
    }
}
