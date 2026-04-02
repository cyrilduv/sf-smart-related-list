import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

import getRelatedRecords from '@salesforce/apex/SmartRelatedListController.getRelatedRecords';
import getColumnDefinitions from '@salesforce/apex/SmartRelatedListController.getColumnDefinitions';
import getObjectLabel from '@salesforce/apex/SmartRelatedListController.getObjectLabel';

import labelSuccess from '@salesforce/label/c.SRL_Success';
import labelRecordsUpdated from '@salesforce/label/c.SRL_RecordsUpdated';
import labelErrorSaving from '@salesforce/label/c.SRL_ErrorSavingRecords';
import labelConfigError from '@salesforce/label/c.SRL_ConfigError';
import labelInvalidColorTitle from '@salesforce/label/c.SRL_InvalidColorRulesTitle';
import labelInvalidColorMsg from '@salesforce/label/c.SRL_InvalidColorRulesMessage';
import labelNoRecords from '@salesforce/label/c.SRL_NoRecordsFound';
import labelRelatedRecords from '@salesforce/label/c.SRL_RelatedRecords';
import labelShowingRecords from '@salesforce/label/c.SRL_ShowingRecords';

const DEBOUNCE_MS = 300;
const SERVER_ROW_LIMIT = 2000;

// Colour tokens admins use in colorRules JSON, e.g. {"Hot":"red","Cold":"blue"}
const COLOR_MAP = {
    red: '#e74c3c',
    orange: '#e67e22',
    green: '#27ae60',
    blue: '#2980b9',
    grey: '#95a5a6'
};
const DEFAULT_COLOR = COLOR_MAP.grey;

export default class SmartRelatedList extends NavigationMixin(LightningElement) {

    // App Builder properties
    @api recordId;
    @api title;
    @api childObjectApiName;
    @api parentFieldApiName;
    @api fieldsToDisplay;
    @api sortableFields;
    @api rowLimit = 10;
    @api enableSearch = false;
    @api enableInlineEdit = false;
    @api enableExport = false;
    @api colorField;
    @api colorRules;
    @api primaryActionLabel;
    @api enableNewRecord = false;

    @track columns = [];
    @track allRecords = [];
    @track draftValues = [];

    searchTerm = '';
    sortedBy;
    sortedDirection = 'asc';
    currentPage = 1;
    isLoading = true;
    errorMessage;
    objectLabel;

    _wiredRecordsResult;
    _debounceTimer;
    _sortableSet;
    _parsedColorRules;

    connectedCallback() {
        if (!this.childObjectApiName || !this.parentFieldApiName) {
            this.errorMessage = labelConfigError;
            this.isLoading = false;
            return;
        }

        this._sortableSet = this.sortableFields
            ? new Set(this.sortableFields.split(',').map(f => f.trim()))
            : null;

        this._parsedColorRules = this._parseColorRules();
    }

    // --- Wire adapters ---

    @wire(getObjectLabel, { objectApiName: '$childObjectApiName' })
    wiredObjectLabel({ data, error }) {
        if (data) {
            this.objectLabel = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.warn('[smartRelatedList] Could not fetch object label:', this._reduceError(error));
            this.objectLabel = this.childObjectApiName;
        }
    }

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

    // --- Computed properties ---

    get cardHeader() {
        const label = this.title || this.objectLabel || this.childObjectApiName || labelRelatedRecords;
        return `${label} · ${this.filteredRecords.length}`;
    }

    get hasColumns() {
        return this.columns && this.columns.length > 0;
    }

    get noData() {
        return !this.isLoading && this.filteredRecords.length === 0;
    }

    get emptyMessage() {
        const label = this.objectLabel || this.childObjectApiName || '';
        return labelNoRecords.replace('{0}', label);
    }

    get hasUnsavedChanges() {
        return this.enableInlineEdit && this.draftValues.length > 0;
    }

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

    // Data pipeline: allRecords → filteredRecords → sortedRecords → paginatedRecords

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

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.rowLimit;
        return this.sortedRecords.slice(start, start + this.rowLimit);
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredRecords.length / this.rowLimit));
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get showPagination() {
        return this.filteredRecords.length > this.rowLimit;
    }

    get paginationLabel() {
        const total = this.filteredRecords.length;
        const start = Math.min((this.currentPage - 1) * this.rowLimit + 1, total);
        const end = Math.min(this.currentPage * this.rowLimit, total);
        return labelShowingRecords
            .replace('{0}', start)
            .replace('{1}', end)
            .replace('{2}', total);
    }

    // --- Event handlers ---

    handleSearchChange(event) {
        clearTimeout(this._debounceTimer);
        const value = event.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.searchTerm = value;
            this.currentPage = 1;
        }, DEBOUNCE_MS);
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

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

    handleCellChange(event) {
        this.draftValues = event.detail.draftValues;
    }

    async handleSaveAll() {
        this.isLoading = true;
        const records = this.draftValues.map(draft => ({ fields: { ...draft } }));
        const promises = records.map(rec => updateRecord(rec));

        try {
            await Promise.all(promises);
            this.dispatchEvent(
                new ShowToastEvent({ title: labelSuccess, message: labelRecordsUpdated, variant: 'success' })
            );
            this.draftValues = [];
            await refreshApex(this._wiredRecordsResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: labelErrorSaving,
                    message: this._reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelEdit() {
        this.draftValues = [];
    }

    handleExportCsv() {
        const records = this.sortedRecords;
        if (!records.length) return;

        const exportCols = this.columns.filter(c => c.type !== 'action' && c.type !== 'button');
        const fieldApis = exportCols.map(c => c.fieldName);
        const headers = exportCols.map(c => c.label);

        // Name is rendered as a button column so it gets filtered out above — re-add it
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
        const blob = new Blob([csvString], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = `${this.objectLabel || this.childObjectApiName || 'export'}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(link.href);
    }

    // --- Private helpers ---

    _buildColumns(columnDefs) {
        const cols = columnDefs.map((col, index) => {
            const def = {
                label: col.label,
                fieldName: col.fieldName,
                type: this._mapFieldType(col.type),
                sortable: this._sortableSet ? this._sortableSet.has(col.fieldName) : true
            };

            if (this.enableInlineEdit && col.updateable) {
                if (col.picklistValues && col.picklistValues.length > 0) {
                    def.type = 'picklist';
                    def.typeAttributes = { options: col.picklistValues };
                }
                def.editable = true;
            }

            if (col.fieldName === 'Name') {
                def.type = 'button';
                def.typeAttributes = {
                    label: { fieldName: 'Name' },
                    name: 'navigate_to_record',
                    variant: 'base'
                };
                def.fieldName = 'Id';
            }

            if (index === 0 && this.colorField && this._parsedColorRules) {
                def.cellAttributes = {
                    style: { fieldName: '_rowColorStyle' }
                };
            }

            return def;
        });

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

    _parseColorRules() {
        if (!this.colorRules) return null;
        try {
            return JSON.parse(this.colorRules);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(
                `[smartRelatedList] Invalid colorRules JSON: "${this.colorRules}". ` +
                `Expected format: {"FieldValue":"colorToken"}. Error: ${e.message}`
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: labelInvalidColorTitle,
                    message: labelInvalidColorMsg,
                    variant: 'warning'
                })
            );
            return null;
        }
    }

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

    _reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
