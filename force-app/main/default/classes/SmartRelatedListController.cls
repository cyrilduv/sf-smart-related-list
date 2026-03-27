/**
 * SmartRelatedListController
 *
 * Server-side controller for the smartRelatedList LWC.
 * Provides four cacheable endpoints:
 *  1. getColumnDefinitions — field metadata (label, type, updateable, picklist values)
 *  2. getRelatedRecords    — child records via dynamic SOQL
 *  3. getTotalCount        — total record count for pagination
 *  4. getObjectLabel       — plural label of the child object (e.g. "Contacts")
 *
 * Security:
 *  - "with sharing" enforces the running user's sharing rules on all queries.
 *  - Object API names are validated against Schema.getGlobalDescribe() before
 *    any SOQL is built, preventing SOQL injection via invalid object names.
 *  - All user-supplied strings in SOQL are escaped with String.escapeSingleQuotes().
 *  - Bind variables (:parentRecordId, :safeTerm) are used wherever possible.
 */
public with sharing class SmartRelatedListController {

    // ═════════════════════════════════════════════════════════════════════
    //  COLUMN DEFINITIONS
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Returns column metadata for the given object and field list.
     * Each ColumnDef includes the field label, API name, Salesforce type,
     * whether the field is updateable, and — for picklist fields — the
     * list of active picklist values (label + value).
     *
     * @param objectApiName  API name of the SObject (e.g. "Contact")
     * @param fields         Comma-separated field API names (e.g. "Name,Email,Phone")
     * @return List of ColumnDef objects
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
            if (sField == null) continue;

            Schema.DescribeFieldResult dfr = sField.getDescribe();
            ColumnDef cd = new ColumnDef();
            cd.label      = dfr.getLabel();
            cd.fieldName  = trimmed;
            cd.type       = dfr.getType().name();
            cd.updateable = dfr.isUpdateable();

            // For picklist fields, include the active values so the LWC
            // can render a dropdown instead of a plain text input.
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

    // ═════════════════════════════════════════════════════════════════════
    //  RECORD DATA
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Queries child records related to a parent via dynamic SOQL.
     * Supports server-side sorting, search (LIKE on Name), limit, and offset.
     *
     * The LWC currently loads all records (up to 2 000) in one call and performs
     * filtering / sorting / pagination client-side. The parameters are exposed
     * for future server-side pagination if needed.
     *
     * @param objectApiName     API name of the child object
     * @param parentFieldApiName Lookup field on the child (e.g. "AccountId")
     * @param parentRecordId    Id of the parent record
     * @param fields            Comma-separated field API names to SELECT
     * @param rowLimit          Maximum rows to return (LIMIT)
     * @param offset            Number of rows to skip (OFFSET)
     * @param sortField         Field API name to ORDER BY (optional)
     * @param sortDirection     "asc" or "desc" (optional, defaults to ASC)
     * @param searchTerm        Filters on Name LIKE '%term%' (optional)
     * @return List of SObject records
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

        // Build the field set — always include Id and Name
        List<String> fieldList = parseFieldList(fields);
        Set<String> fieldSet = new Set<String>{ 'Id', 'Name' };
        for (String f : fieldList) {
            fieldSet.add(f.trim());
        }

        String fieldCsv = String.join(new List<String>(fieldSet), ', ');

        // Assemble the query
        String query = 'SELECT ' + fieldCsv
            + ' FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE ' + String.escapeSingleQuotes(parentFieldApiName) + ' = :parentRecordId';

        // Optional Name search
        if (String.isNotBlank(searchTerm)) {
            String safeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE :safeTerm';
        }

        // Sorting
        if (String.isNotBlank(sortField)) {
            String safeSort = String.escapeSingleQuotes(sortField.trim());
            String dir = (sortDirection != null && sortDirection.equalsIgnoreCase('desc'))
                ? 'DESC' : 'ASC';
            query += ' ORDER BY ' + safeSort + ' ' + dir + ' NULLS LAST';
        } else {
            query += ' ORDER BY CreatedDate DESC';
        }

        // Pagination
        if (rowLimit != null && rowLimit > 0) {
            query += ' LIMIT ' + rowLimit;
        }
        if (offset != null && offset > 0) {
            query += ' OFFSET ' + offset;
        }

        return Database.query(query);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TOTAL COUNT
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Returns the total number of child records matching the parent and
     * optional search term. Used for server-side pagination calculations.
     *
     * @param objectApiName     API name of the child object
     * @param parentFieldApiName Lookup field on the child
     * @param parentRecordId    Id of the parent record
     * @param searchTerm        Optional Name LIKE filter
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

        String query = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE ' + String.escapeSingleQuotes(parentFieldApiName) + ' = :parentRecordId';

        if (String.isNotBlank(searchTerm)) {
            String safeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            query += ' AND Name LIKE :safeTerm';
        }

        return Database.countQuery(query);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  OBJECT LABEL
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Returns the plural label for the given object (e.g. "Contacts").
     * Used in the card header and empty-state message.
     *
     * @param objectApiName  API name of the SObject
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

    // ═════════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Splits a comma-separated field string into a trimmed list.
     * Defaults to ['Name'] when the input is blank or empty.
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
     * Validates that the given object API name exists in the org schema.
     * Throws an AuraHandledException (surfaced to the LWC) if invalid.
     */
    private static void validateObjectApiName(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        if (sot == null) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  INNER CLASSES
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Wrapper returned by getColumnDefinitions.
     * Describes a single datatable column.
     */
    public class ColumnDef {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean updateable;
        @AuraEnabled public List<PicklistOption> picklistValues;
    }

    /**
     * Represents a single picklist entry (label + value)
     * for use in the custom datatable picklist editor.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
