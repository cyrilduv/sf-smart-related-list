/*
 * Extends lightning-datatable with a "picklist" column type that uses a native
 * <select> instead of lightning-combobox (which conflicts with datatable internals).
 */
import LightningDatatable from 'lightning/datatable';
import picklistEditTemplate from './picklistEditTemplate.html';
import picklistTemplate from './picklistTemplate.html';

export default class CustomDatatable extends LightningDatatable {

    static customTypes = {
        picklist: {
            editTemplate: picklistEditTemplate,
            standardCellLayout: true,
            template: picklistTemplate,
            typeAttributes: ['options']
        }
    };

    constructor() {
        super();
        /*
         * Stop native <select> change events from reaching the datatable's
         * internal combobox handler, which throws on unexpected event shapes.
         */
        this.template.addEventListener('change', (event) => {
            const { target } = event;
            if (target && target.tagName === 'SELECT' && target.closest('.slds-select_container')) {
                event.stopImmediatePropagation();
            }
        }, true);
    }

    handlePicklistChange(event) {
        event.stopPropagation();
        event.preventDefault();
        const newValue = event.target.value;
        this.dispatchEvent(
            new CustomEvent('cellchange', {
                composed: true,
                bubbles: true,
                detail: {
                    draftValues: [{ Id: this.currentRowId, [this.currentColumnFieldName]: newValue }]
                }
            })
        );
    }

    get currentRowId() {
        const row = this.template.querySelector('tr.slds-is-edited');
        return row?.dataset?.rowKeyValue;
    }

    get currentColumnFieldName() {
        const cell = this.template.querySelector('td.slds-is-edited');
        return cell?.dataset?.columnFieldName;
    }
}
