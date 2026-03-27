/**
 * smartRelatedList — A fully configurable related list Lightning Web Component.
 *
 * Features:
 *  - Dynamic column definitions driven by App Builder configuration
 *  - Client-side search, sorting, and pagination
 *  - Inline editing with picklist support (via c-custom-datatable)
 *  - Row colour-coding using a configurable field + JSON colour rules
 *  - CSV export of all loaded records
 *  - "New" button to create child records pre-populated with the parent lookup
 *  - Row-level primary action button (e.g. "Edit") for quick record navigation
 *
 * @alias SmartRelatedList
 * @extends NavigationMixin(LightningElement)
 */
import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

import getRelatedRecords from '@salesforce/apex/SmartRelatedListController.getRelatedRecords';
import getColumnDefinitions from '@salesforce/apex/SmartRelatedListController.getColumnDefinitions';
import getObjectLabel from '@salesforce/apex/SmartRelatedListController.getObjectLabel';

// ── Constants ────────────────────────────────────────────────────────────────

/** Debounce delay (ms) for the search input to avoid excessive re-filtering. */
const DEBOUNCE_MS = 300;

/** Maximum number of records loaded from the server in a single wire call. */
const SERVER_ROW_LIMIT = 2000;

/**
 * Mapping of colour tokens (used in the colorRules JSON) to hex values.
 * Admins reference these tokens in App Builder — e.g. {"Hot":"red","Cold":"blue"}.
 */
const COLOR_MAP = {
    red: '#e74c3c',
    orange: '#e67e22',
    green: '#27ae60',
    blue: '#2980b9',
    grey: '#95a5a6'
};

/** Fallback colour when a field value has no matching rule. */
const DEFAULT_COLOR = COLOR_MAP.grey;

// ── Component ────────────────────────────────────────────────────────────────

export default class SmartRelatedList extends NavigationMixin(LightningElement) {

    // ── App Builder properties (set by admins in Lightning App Builder) ───

    /** Record Id of the parent record — auto-injected on record pages. */
    @api recordId;

    /** Card header label (e.g. "Contacts"). */
    @api title;

    /** API name of the child object to query (e.g. "Contact"). */
    @api childObjectApiName;

    /** Lookup/master-detail field on the child that points to the parent (e.g. "AccountId"). */
    @api parentFieldApiName;

    /** Comma-separated field API names to show as columns (e.g. "Name,Email,Phone"). */
    @api fieldsToDisplay;

    /** Comma-separated field API names that should be sortable. Leave blank for all. */
    @api sortableFields;

    /** Number of records displayed per page (default 10). */
    @api rowLimit = 10;

    /** When true, renders a search bar above the table. */
    @api enableSearch = false;

    /** When true, columns marked updateable become editable inline. */
    @api enableInlineEdit = false;

    /** When true, shows a CSV export button in the toolbar. */
    @api enableExport = false;

    /** API name of a text/picklist field whose value drives row colour-coding. */
    @api colorField;

    /** JSON string mapping field values to colour tokens — e.g. {"Hot":"red","Warm":"orange"}. */
    @api colorRules;

    /** Label for the row-level primary action button (e.g. "Edit"). Omit to hide. */
    @api primaryActionLabel;

    /** When true, shows a "New" button that creates a child record pre-linked to the parent. */
    @api enableNewRecord = false;

    // ── Reactive internal state ──────────────────────────────────────────

    /** Column definitions passed to the datatable. */
    @track columns = [];

    /** All records loaded from the server (enriched with computed fields). */
    @track allRecords = [];

    /** Pending inline-edit changes tracked by the datatable. */
    @track draftValues = [];

    // ── Non-reactive internal state ─────────────────────────────────────

    searchTerm = '';
    sortedBy;
    sortedDirection = 'asc';
    currentPage = 1;
    isLoading = true;
    errorMessage;
    objectLabel;

    /** Cached wire result used by refreshApex after inline-edit save. */
    _wiredRecordsResult;

    /** Timer handle for search debounce. */
    _debounceTimer;

    /** Pre-computed Set of sortable field names, or null if all are sortable. */
    _sortableSet;

    /** Parsed colorRules JSON object, or null when unconfigured / invalid. */
    _parsedColorRules;

    // ═════════════════════════════════════════════════════════════════════
    //  LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    connectedCallback() {
        this._sortableSet = this.sortableFields
            ? new Set(this.sortableFields.split(',').map(f => f.trim()))
            : null;

        this._parsedColorRules = this._parseColorRules();
    }

    // ═════════════════════════════════════════════════════════════════════
    //  WIRE ADAPTERS
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Fetches the plural label for the child object (e.g. "Contacts").
     * Used in the card header and empty-state message.
     */
    @wire(getObjectLabel, { objectApiName: '$childObjectApiName' })
    wiredObjectLabel({ data, error }) {
        if (data) {
            this.objectLabel = data;
        } else if (error) {
            this.objectLabel = this.childObjectApiName;
        }
    }

    /**
     * Fetches column metadata (label, type, updateable, picklist values)
     * from Apex describe calls and builds the datatable column array.
     */
    @wire(getColumnDefinitions, {
        objectApiName: '$childObjectApiName',
        fields: '$fieldsToDisplay'
    })
    wiredColumns({ error, data }) {
        if (data) {
            this.columns = this._buildColumns(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.errorMessage = this._reduceError(error);
        }
    }

    /**
     * Loads up to SERVER_ROW_LIMIT child records.
     * All filtering, sorting, and pagination happens client-side.
     */
    @wire(getRelatedRecords, {
        objectApiName: '$childObjectApiName',
        parentFieldApiName: '$parentFieldApiName',
        parentRecordId: '$recordId',
        fields: '$fieldsToDisplay',
        rowLimit: SERVER_ROW_LIMIT,
        offset: 0,
        sortField: null,
        sortDirection: null,
        searchTerm: null
    })
    wiredRecords(result) {
        this._wiredRecordsResult = result;
        const { error, data } = result;
        this.isLoading = false;
        if (data) {
            this.allRecords = this._enrichRecords(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.errorMessage = this._reduceError(error);
            this.allRecords = [];
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  COMPUTED PROPERTIES — HEADER & STATE
    // ═════════════════════════════════════════════════════════════════════

    /** Card title with record count badge — e.g. "Contacts · 12". */
    get cardHeader() {
        const label = this.title || this.objectLabel || this.childObjectApiName || 'Related Records';
        return `${label} · ${this.filteredRecords.length}`;
    }

    /** True when column definitions have been loaded. */
    get hasColumns() {
        return this.columns && this.columns.length > 0;
    }

    /** True when the table has loaded but contains zero rows. */
    get noData() {
        return !this.isLoading && this.filteredRecords.length === 0;
    }

    /** Message shown in the empty state — e.g. "No Contacts records found." */
    get emptyMessage() {
        const label = this.objectLabel || this.childObjectApiName || '';
        return `No ${label} records found.`;
    }

    /** True when inline edit is enabled and there are unsaved draft changes. */
    get hasUnsavedChanges() {
        return this.enableInlineEdit && this.draftValues.length > 0;
    }

    /**
     * Returns columns with or without the editable flag.
     * When inline edit is disabled, strips editable from every column
     * so the datatable renders in read-only mode.
     */
    get activeColumns() {
        if (this.enableInlineEdit) {
            return this.columns;
        }
        return this.columns.map(col => {
            const clone = { ...col };
            delete clone.editable;
            return clone;
        });
    }

    // ═════════════════════════════════════════════════════════════════════
    //  COMPUTED PROPERTIES — DATA PIPELINE
    //  allRecords → filteredRecords → sortedRecords → paginatedRecords
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Client-side filter: matches the search term against every visible
     * field value in each row. Internal fields (prefixed with _) are skipped.
     */
    get filteredRecords() {
        if (!this.searchTerm) {
            return this.allRecords;
        }
        const term = this.searchTerm.toLowerCase();
        return this.allRecords.filter(row =>
            Object.keys(row).some(key => {
                if (key.startsWith('_')) return false;
                const val = row[key];
                return val != null && String(val).toLowerCase().includes(term);
            })
        );
    }

    /**
     * Client-side sort on the currently filtered data.
     * Supports string and numeric comparison with null-safe fallback.
     */
    get sortedRecords() {
        const data = [...this.filteredRecords];
        if (!this.sortedBy) return data;
        const field = this.sortedBy;
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        return data.sort((a, b) => {
            let valA = a[field] ?? '';
            let valB = b[field] ?? '';
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            if (valA < valB) return -1 * dir;
            if (valA > valB) return 1 * dir;
            return 0;
        });
    }

    /** Slices the sorted data to the current page window. */
    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.rowLimit;
        return this.sortedRecords.slice(start, start + this.rowLimit);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  COMPUTED PROPERTIES — PAGINATION
    // ═════════════════════════════════════════════════════════════════════

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredRecords.length / this.rowLimit));
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    /** Only show pagination controls when records exceed a single page. */
    get showPagination() {
        return this.filteredRecords.length > this.rowLimit;
    }

    /** Descriptive label — e.g. "Showing 1–10 of 42 records". */
    get paginationLabel() {
        const total = this.filteredRecords.length;
        const start = Math.min((this.currentPage - 1) * this.rowLimit + 1, total);
        const end = Math.min(this.currentPage * this.rowLimit, total);
        return `Showing ${start}–${end} of ${total} records`;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  EVENT HANDLERS — SEARCH, SORT, PAGINATION
    // ═════════════════════════════════════════════════════════════════════

    /** Debounced handler for the search input — resets to page 1 on each change. */
    handleSearchChange(event) {
        clearTimeout(this._debounceTimer);
        const value = event.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.searchTerm = value;
            this.currentPage = 1;
        }, DEBOUNCE_MS);
    }

    /** Handles column-header sort clicks from the datatable. */
    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
    }

    handlePreviousPage() {
        if (this.currentPage > 1) this.currentPage--;
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage++;
    }

    // ═════════════════════════════════════════════════════════════════════
    //  EVENT HANDLERS — NAVIGATION
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Opens the standard "New" record form for the child object,
     * pre-populating the parent lookup field with the current recordId.
     */
    handleNewRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.childObjectApiName,
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `${this.parentFieldApiName}=${this.recordId}`
            }
        });
    }

    /**
     * Handles row-level actions:
     *  - navigate_to_record: opens the child record in view mode (same tab)
     *  - primary_action: opens the child record in edit mode
     */
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'navigate_to_record') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: this.childObjectApiName,
                    actionName: 'view'
                }
            });
        } else if (actionName === 'primary_action') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: this.childObjectApiName,
                    actionName: 'edit'
                }
            });
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  EVENT HANDLERS — INLINE EDIT
    // ═════════════════════════════════════════════════════════════════════

    /** Captures draft values on every cell change. */
    handleCellChange(event) {
        this.draftValues = event.detail.draftValues;
    }

    /**
     * Saves all pending draft values using Lightning Data Service (updateRecord).
     * On success: shows a toast, clears drafts, and refreshes the wire cache.
     * On failure: shows an error toast with the first failing field message.
     */
    async handleSaveAll() {
        this.isLoading = true;
        const records = this.draftValues.map(draft => ({ fields: { ...draft } }));
        const promises = records.map(rec => updateRecord(rec));

        try {
            await Promise.all(promises);
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Success', message: 'Records updated.', variant: 'success' })
            );
            this.draftValues = [];
            await refreshApex(this._wiredRecordsResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error saving records',
                    message: this._reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    /** Discards all pending inline-edit changes. */
    handleCancelEdit() {
        this.draftValues = [];
    }

    // ═════════════════════════════════════════════════════════════════════
    //  CSV EXPORT
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Builds a CSV string from ALL sorted records (not just the current page)
     * and opens it in a new browser tab via a data: URI.
     * A BOM character (\uFEFF) is prepended so Excel handles UTF-8 correctly.
     */
    handleExportCsv() {
        const records = this.sortedRecords;
        if (!records.length) return;

        // Exclude non-data columns (action menu, Name button)
        const exportCols = this.columns.filter(c => c.type !== 'action' && c.type !== 'button');
        const fieldApis = exportCols.map(c => c.fieldName);
        const headers = exportCols.map(c => c.label);

        // The Name column is rendered as a button (type: 'button') so it was
        // excluded above — re-add it as the first column in the CSV output.
        if (!fieldApis.includes('Name')) {
            fieldApis.unshift('Name');
            headers.unshift('Name');
        }

        const csvRows = [headers.join(',')];
        records.forEach(row => {
            const vals = fieldApis.map(field => {
                let val = row[field] ?? '';
                val = String(val).replace(/"/g, '""');
                return `"${val}"`;
            });
            csvRows.push(vals.join(','));
        });

        const csvString = '\uFEFF' + csvRows.join('\r\n');
        const encodedUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvString);
        window.open(encodedUri);
    }

    // ═════════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Converts Apex ColumnDef objects into lightning-datatable column definitions.
     *
     * - Maps Salesforce field types to datatable types (text, number, date, etc.)
     * - Marks columns as sortable based on the sortableFields config
     * - Enables inline editing for updateable fields (picklists get the custom 'picklist' type)
     * - Converts the Name column to a clickable button for same-tab navigation
     * - Adds a colour-indicator style to the first column when colour rules are active
     * - Appends a row-level action column when primaryActionLabel is configured
     *
     * @param {Array} columnDefs — ColumnDef objects from Apex
     * @returns {Array} Column definitions for the datatable
     */
    _buildColumns(columnDefs) {
        const cols = columnDefs.map((col, index) => {
            const def = {
                label: col.label,
                fieldName: col.fieldName,
                type: this._mapFieldType(col.type),
                sortable: this._sortableSet ? this._sortableSet.has(col.fieldName) : true
            };

            // Inline edit: use the custom 'picklist' type for picklist fields,
            // standard editable: true for everything else
            if (this.enableInlineEdit && col.updateable) {
                if (col.picklistValues && col.picklistValues.length > 0) {
                    def.type = 'picklist';
                    def.typeAttributes = { options: col.picklistValues };
                    def.editable = true;
                } else {
                    def.editable = true;
                }
            }

            // Name column: render as a clickable button (navigates in same tab)
            if (col.fieldName === 'Name') {
                def.type = 'button';
                def.typeAttributes = {
                    label: { fieldName: 'Name' },
                    name: 'navigate_to_record',
                    variant: 'base'
                };
                def.fieldName = 'Id';
            }

            // Colour coding: apply an inline border-left style to the first column
            if (index === 0 && this.colorField && this._parsedColorRules) {
                def.cellAttributes = {
                    style: { fieldName: '_rowColorStyle' }
                };
            }

            return def;
        });

        // Optional row-level action button (e.g. "Edit")
        if (this.primaryActionLabel) {
            cols.push({
                type: 'action',
                typeAttributes: {
                    rowActions: [
                        { label: this.primaryActionLabel, name: 'primary_action' }
                    ]
                }
            });
        }

        return cols;
    }

    /**
     * Enriches raw SObject records with computed fields used by the template:
     *  - _rowColorStyle: inline CSS for the colour-coded left border
     *
     * @param {Array} records — raw SObject records from the wire
     * @returns {Array} Enriched record objects
     */
    _enrichRecords(records) {
        return records.map(record => {
            const row = { ...record };

            if (this.colorField && this._parsedColorRules) {
                const fieldValue = record[this.colorField];
                const colorToken = this._parsedColorRules[fieldValue];
                const hex = (colorToken && COLOR_MAP[colorToken]) ? COLOR_MAP[colorToken] : DEFAULT_COLOR;
                row._rowColorStyle = `border-left: 4px solid ${hex}`;
            }

            return row;
        });
    }

    /**
     * Safely parses the colorRules JSON string.
     * Returns null on empty input or invalid JSON (no error thrown).
     *
     * @returns {Object|null} Parsed colour rules or null
     */
    _parseColorRules() {
        if (!this.colorRules) return null;
        try {
            return JSON.parse(this.colorRules);
        } catch (e) {
            return null;
        }
    }

    /**
     * Maps a Salesforce Schema.DisplayType name to a lightning-datatable column type.
     *
     * @param {string} sfType — e.g. "STRING", "CURRENCY", "DATE"
     * @returns {string} Datatable type — e.g. "text", "currency", "date"
     */
    _mapFieldType(sfType) {
        const typeMap = {
            STRING: 'text',
            TEXTAREA: 'text',
            BOOLEAN: 'boolean',
            INTEGER: 'number',
            DOUBLE: 'number',
            CURRENCY: 'currency',
            PERCENT: 'percent',
            DATE: 'date',
            DATETIME: 'date',
            EMAIL: 'email',
            PHONE: 'phone',
            URL: 'url',
            REFERENCE: 'text',
            PICKLIST: 'text'
        };
        return typeMap[sfType] || 'text';
    }

    /**
     * Extracts a human-readable message from various Apex/LDS error shapes.
     *
     * @param {Object|string} error — error from a wire adapter or imperative call
     * @returns {string} Error message string
     */
    _reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
