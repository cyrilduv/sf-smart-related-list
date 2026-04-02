/**
 * Server-side controller for the smartRelatedList LWC.
 * Uses "with sharing" for record-level access, validates all dynamic SOQL
 * identifiers against Schema describe, and enforces FLS via stripInaccessible.
 */
public with sharing class SmartRelatedListController {

    /**
     * Returns column metadata for the given object and field list.
     * Fields the running user cannot access are silently excluded.
     */
    @AuraEnabled(cacheable=true)
    public static List<ColumnDef> getColumnDefinitions(
        String objectApiName,
        String fields
    ) {
        validateObjectApiName(objectApiName);

        List<String> fieldList = parseFieldList(fields);
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields.getMap();

        List<ColumnDef> defs = new List<ColumnDef>();
        for (String fieldApi : fieldList) {
            String trimmed = fieldApi.trim();
            Schema.SObjectField sField = fieldMap.get(trimmed.toLowerCase());
            if (sField == null) {
                throw new AuraHandledException(
                    'Invalid field "' + trimmed + '" on object ' + objectApiName
                );
            }

            Schema.DescribeFieldResult dfr = sField.getDescribe();
            if (!dfr.isAccessible()) continue;

            ColumnDef cd = new ColumnDef();
            cd.label      = dfr.getLabel();
            cd.fieldName  = trimmed;
            cd.type       = dfr.getType().name();
            cd.updateable = dfr.isUpdateable();

            if (dfr.getType() == Schema.DisplayType.PICKLIST
                || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
                cd.picklistValues = new List<PicklistOption>();
                for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                    if (pe.isActive()) {
                        cd.picklistValues.add(new PicklistOption(pe.getLabel(), pe.getValue()));
                    }
                }
            }

            defs.add(cd);
        }
        return defs;
    }

    /**
     * Queries child records related to a parent via dynamic SOQL.
     * All field/object identifiers are validated against describe before query construction.
     * Results are FLS-stripped before returning.
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getRelatedRecords(
        String objectApiName,
        String parentFieldApiName,
        Id parentRecordId,
        String fields,
        Integer rowLimit,
        Integer offset,
        String sortField,
        String sortDirection,
        String searchTerm
    ) {
        validateObjectApiName(objectApiName);

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields.getMap();

        validateFieldApiName(parentFieldApiName, fieldMap, objectApiName);

        List<String> fieldList = parseFieldList(fields);
        Set<String> fieldSet = new Set<String>{ 'Id' };
        for (String f : fieldList) {
            String trimmed = f.trim();
            validateFieldApiName(trimmed, fieldMap, objectApiName);
            fieldSet.add(trimmed);
        }

        if (fieldMap.containsKey('name')) {
            fieldSet.add('Name');
        }

        String fieldCsv = String.join(new List<String>(fieldSet), ', ');

        String query = 'SELECT ' + fieldCsv
            + ' FROM ' + objectApiName
            + ' WHERE ' + parentFieldApiName + ' = :parentRecordId';

        String safeTerm;
        if (String.isNotBlank(searchTerm) && fieldMap.containsKey('name')) {
            safeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE :safeTerm';
        }

        if (String.isNotBlank(sortField)) {
            String trimmedSort = sortField.trim();
            validateFieldApiName(trimmedSort, fieldMap, objectApiName);
            String dir = (sortDirection != null && sortDirection.equalsIgnoreCase('desc'))
                ? 'DESC' : 'ASC';
            query += ' ORDER BY ' + trimmedSort + ' ' + dir + ' NULLS LAST';
        } else {
            query += ' ORDER BY CreatedDate DESC';
        }

        if (rowLimit != null && rowLimit > 0) {
            query += ' LIMIT ' + rowLimit;
        }
        if (offset != null && offset > 0) {
            query += ' OFFSET ' + offset;
        }

        List<SObject> results = Database.query(query);
        return Security.stripInaccessible(AccessType.READABLE, results).getRecords();
    }

    @AuraEnabled(cacheable=true)
    public static Integer getTotalCount(
        String objectApiName,
        String parentFieldApiName,
        Id parentRecordId,
        String searchTerm
    ) {
        validateObjectApiName(objectApiName);

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields.getMap();

        validateFieldApiName(parentFieldApiName, fieldMap, objectApiName);

        String query = 'SELECT COUNT() FROM ' + objectApiName
            + ' WHERE ' + parentFieldApiName + ' = :parentRecordId';

        String safeTerm;
        if (String.isNotBlank(searchTerm) && fieldMap.containsKey('name')) {
            safeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE :safeTerm';
        }

        return Database.countQuery(query);
    }

    @AuraEnabled(cacheable=true)
    public static String getObjectLabel(String objectApiName) {
        validateObjectApiName(objectApiName);
        return Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .getLabelPlural();
    }

    // --- Helpers ---

    private static List<String> parseFieldList(String fields) {
        List<String> result = new List<String>();
        if (String.isNotBlank(fields)) {
            for (String f : fields.split(',')) {
                String trimmed = f.trim();
                if (String.isNotBlank(trimmed)) {
                    result.add(trimmed);
                }
            }
        }
        if (result.isEmpty()) {
            result.add('Name');
        }
        return result;
    }

    private static void validateObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
    }

    // Prevents SOQL injection in field-name positions (SELECT, WHERE, ORDER BY)
    private static void validateFieldApiName(
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap,
        String objectApiName
    ) {
        if (String.isBlank(fieldApiName)) {
            throw new AuraHandledException('Field API name is required.');
        }
        if (!fieldMap.containsKey(fieldApiName.toLowerCase())) {
            throw new AuraHandledException(
                'Invalid field "' + fieldApiName + '" on object ' + objectApiName
            );
        }
    }

    // --- Inner classes ---

    public class ColumnDef {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean updateable;
        @AuraEnabled public List<PicklistOption> picklistValues;
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
