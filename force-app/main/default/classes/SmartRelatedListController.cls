/**
 * @description Server-side controller for the smartRelatedList LWC.
 * Uses "with sharing" for record-level access, validates all dynamic SOQL
 * identifiers against Schema describe, and enforces FLS via stripInaccessible.
 */
public with sharing class SmartRelatedListController {

    /**
     * @description Returns column metadata for the given object and field list.
     * Fields the running user cannot access are excluded via isAccessible().
     * @param objectApiName API name of the SObject (e.g. "Contact")
     * @param fields Comma-separated field API names (e.g. "Name,Email,Phone")
     * @return List of ColumnDef wrapper objects
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
            if (!dfr.isAccessible()) {
                continue;
            }

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
     * @description Queries child records related to a parent via dynamic SOQL.
     * All identifiers are validated against describe before query construction.
     * Results are FLS-stripped via Security.stripInaccessible before returning.
     * @param objectApiName API name of the child object
     * @param parentFieldApiName Lookup field on the child (e.g. "AccountId")
     * @param parentRecordId Id of the parent record
     * @param fields Comma-separated field API names to SELECT
     * @param rowLimit Maximum rows to return
     * @param offset Number of rows to skip
     * @param sortField Field API name to ORDER BY (optional)
     * @param sortDirection "asc" or "desc" (optional)
     * @param searchTerm Filters on Name LIKE (optional)
     * @return List of SObject records with FLS enforced
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

        // All identifiers in this query are validated against Schema describe above. NOPMD
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

        List<SObject> results = Database.query(query); // NOPMD - identifiers validated via describe
        return Security.stripInaccessible(AccessType.READABLE, results).getRecords();
    }

    /**
     * @description Returns the count of child records matching the parent and optional search.
     * @param objectApiName API name of the child object
     * @param parentFieldApiName Lookup field on the child
     * @param parentRecordId Id of the parent record
     * @param searchTerm Optional Name LIKE filter
     * @return Total record count
     */
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

        // All identifiers validated via describe above. NOPMD
        String query = 'SELECT COUNT() FROM ' + objectApiName
            + ' WHERE ' + parentFieldApiName + ' = :parentRecordId';

        String safeTerm;
        if (String.isNotBlank(searchTerm) && fieldMap.containsKey('name')) {
            safeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE :safeTerm';
        }

        return Database.countQuery(query); // NOPMD - identifiers validated via describe
    }

    /**
     * @description Returns the plural label for the given object (e.g. "Contacts").
     * @param objectApiName API name of the SObject
     * @return Plural label string
     */
    @AuraEnabled(cacheable=true)
    public static String getObjectLabel(String objectApiName) {
        validateObjectApiName(objectApiName);
        return Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .getLabelPlural();
    }

    /**
     * @description Splits a comma-separated field string into a trimmed list.
     * Defaults to Name when input is blank.
     * @param fields Comma-separated field API names
     * @return Trimmed list of field names
     */
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

    /**
     * @description Validates the object API name exists in the org schema.
     * @param objectApiName API name to validate
     */
    private static void validateObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException(System.Label.SRL_ObjectApiNameRequired);
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException(
                System.Label.SRL_InvalidObjectApiName + ': ' + objectApiName
            );
        }
    }

    /**
     * @description Validates a field API name exists on the given object.
     * Prevents SOQL injection in field-name positions (SELECT, WHERE, ORDER BY).
     * @param fieldApiName Field API name to validate
     * @param fieldMap The object's field describe map
     * @param objectApiName Object name for error messages
     */
    private static void validateFieldApiName(
        String fieldApiName,
        Map<String, Schema.SObjectField> fieldMap,
        String objectApiName
    ) {
        if (String.isBlank(fieldApiName)) {
            throw new AuraHandledException(System.Label.SRL_FieldApiNameRequired);
        }
        if (!fieldMap.containsKey(fieldApiName.toLowerCase())) {
            throw new AuraHandledException(
                System.Label.SRL_InvalidField + ' "' + fieldApiName + '" on object ' + objectApiName
            );
        }
    }

    /**
     * @description Wrapper for a single datatable column definition.
     */
    public class ColumnDef {
        /** @description Column header label */
        @AuraEnabled public String label;
        /** @description Field API name */
        @AuraEnabled public String fieldName;
        /** @description Salesforce field type name */
        @AuraEnabled public String type;
        /** @description Whether the running user can update this field */
        @AuraEnabled public Boolean updateable;
        /** @description Active picklist entries, null for non-picklist fields */
        @AuraEnabled public List<PicklistOption> picklistValues;
    }

    /**
     * @description Represents a single picklist entry for the custom picklist editor.
     */
    public class PicklistOption {
        /** @description Display label */
        @AuraEnabled public String label;
        /** @description API value */
        @AuraEnabled public String value;

        /**
         * @description Constructs a picklist option.
         * @param label Display label
         * @param value API value
         */
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
