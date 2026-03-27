/**
 * customDatatable — Extends lightning-datatable with a custom "picklist" column type.
 *
 * Standard lightning-datatable renders picklist fields as plain text inputs
 * during inline editing. This extension registers a "picklist" custom type
 * that uses a native HTML <select> dropdown instead, populated with the
 * active picklist values fetched from Apex.
 *
 * Templates:
 *  - picklistTemplate.html     → read-only display (truncated text)
 *  - picklistEditTemplate.html → edit mode (HTML <select> with SLDS styling)
 *
 * Why a native <select> instead of lightning-combobox?
 *  The lightning-combobox component's internal event handling (handleSelect)
 *  conflicts with lightning-datatable's custom edit template lifecycle,
 *  causing script errors. A native <select> avoids this entirely.
 *
 * @alias CustomDatatable
 * @extends LightningDatatable
 */
import LightningDatatable from 'lightning/datatable';
import picklistTemplate from './picklistTemplate.html';
import picklistEditTemplate from './picklistEditTemplate.html';

export default class CustomDatatable extends LightningDatatable {

    /**
     * Registers the "picklist" custom column type.
     *  - template:          read-only view (plain text)
     *  - editTemplate:      edit view (HTML <select> dropdown)
     *  - standardCellLayout: true = wrap in the datatable's standard cell chrome
     *  - typeAttributes:    ['options'] = array of {label, value} picklist entries
     */
    static customTypes = {
        picklist: {
            template: picklistTemplate,
            editTemplate: picklistEditTemplate,
            standardCellLayout: true,
            typeAttributes: ['options']
        }
    };

    constructor() {
        super();
        // Intercept native "change" events from the <select> element during
        // the capture phase. Without this, the event bubbles into the
        // datatable's internal combobox handler and throws a script error.
        this.template.addEventListener('change', (event) => {
            const target = event.target;
            if (target && target.tagName === 'SELECT' && target.closest('.slds-select_container')) {
                event.stopImmediatePropagation();
            }
        }, true);
    }

    /**
     * Handles value selection in the picklist <select>.
     * Dispatches a "cellchange" CustomEvent with the new value so the
     * parent datatable updates its draftValues array.
     */
    handlePicklistChange(event) {
        event.stopPropagation();
        event.preventDefault();
        const newValue = event.target.value;
        this.dispatchEvent(
            new CustomEvent('cellchange', {
                composed: true,
                bubbles: true,
                detail: {
                    draftValues: [{ Id: this._currentRowId, [this._currentColumnFieldName]: newValue }]
                }
            })
        );
    }

    /** Returns the Id of the row currently being edited. */
    get _currentRowId() {
        const row = this.template.querySelector('tr.slds-is-edited');
        return row?.dataset?.rowKeyValue;
    }

    /** Returns the field API name of the column currently being edited. */
    get _currentColumnFieldName() {
        const cell = this.template.querySelector('td.slds-is-edited');
        return cell?.dataset?.columnFieldName;
    }
}
