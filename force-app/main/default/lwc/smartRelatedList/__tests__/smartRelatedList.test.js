import { createElement } from 'lwc';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import SmartRelatedList from 'c/smartRelatedList';
import getRelatedRecords from '@salesforce/apex/SmartRelatedListController.getRelatedRecords';
import getColumnDefinitions from '@salesforce/apex/SmartRelatedListController.getColumnDefinitions';
import getObjectLabel from '@salesforce/apex/SmartRelatedListController.getObjectLabel';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/SmartRelatedListController.getRelatedRecords',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SmartRelatedListController.getColumnDefinitions',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SmartRelatedListController.getObjectLabel',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Mock lightning/navigation
const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => ({
    NavigationMixin: (Base) => {
        return class extends Base {
            [Symbol.for('lwc-navigation-navigate')] = mockNavigate;
        };
    }
}), { virtual: true });

// Flush promises helper
const flushPromises = () => new Promise(process.nextTick);

const MOCK_COLUMNS = [
    { label: 'Last Name', fieldName: 'LastName', type: 'STRING', updateable: true, picklistValues: null },
    { label: 'Email', fieldName: 'Email', type: 'EMAIL', updateable: true, picklistValues: null },
    { label: 'Name', fieldName: 'Name', type: 'STRING', updateable: false, picklistValues: null }
];

const MOCK_RECORDS = [];
for (let i = 0; i < 15; i++) {
    MOCK_RECORDS.push({
        Id: `003000000000${String(i).padStart(3, '0')}`,
        Name: `Test Contact ${String(i).padStart(2, '0')}`,
        LastName: `Contact ${String(i).padStart(2, '0')}`,
        Email: `test${i}@example.com`
    });
}

function createComponent(props = {}) {
    const element = createElement('c-smart-related-list', { is: SmartRelatedList });
    Object.assign(element, {
        recordId: '001000000000001',
        childObjectApiName: 'Contact',
        parentFieldApiName: 'AccountId',
        fieldsToDisplay: 'LastName,Email',
        rowLimit: 10,
        ...props
    });
    document.body.appendChild(element);
    return element;
}

// Emit wire adapter data
function emitWireData(wireAdapter, data, error) {
    wireAdapter.emit(data !== undefined ? { data, error: undefined } : { data: undefined, error });
}

describe('c-smart-related-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // ───────────────────────────────────────────────
    //  Rendering & Data Pipeline
    // ───────────────────────────────────────────────

    describe('data pipeline', () => {
        it('displays loading spinner initially', () => {
            const element = createComponent();
            const spinner = element.shadowRoot.querySelector('lightning-spinner');
            expect(spinner).not.toBeNull();
        });

        it('renders the card header with record count', async () => {
            const element = createComponent({ title: 'Contacts' });

            // Emit column and record data
            emitWireData(getColumnDefinitions, MOCK_COLUMNS);
            emitWireData(getRelatedRecords, { data: MOCK_RECORDS });
            await flushPromises();

            const card = element.shadowRoot.querySelector('lightning-card');
            expect(card.title).toContain('Contacts');
        });

        it('shows empty state when no records returned', async () => {
            const element = createComponent();

            emitWireData(getColumnDefinitions, MOCK_COLUMNS);
            emitWireData(getRelatedRecords, { data: [] });
            await flushPromises();

            const emptyState = element.shadowRoot.querySelector('.empty-state');
            expect(emptyState).not.toBeNull();
        });

        it('shows error banner on wire error', async () => {
            const element = createComponent();

            emitWireData(getColumnDefinitions, MOCK_COLUMNS);
            emitWireData(getRelatedRecords, undefined, { body: { message: 'Test error' } });
            await flushPromises();

            const errorDiv = element.shadowRoot.querySelector('.slds-text-color_error');
            expect(errorDiv).not.toBeNull();
            expect(errorDiv.textContent).toBe('Test error');
        });
    });

    // ───────────────────────────────────────────────
    //  Search
    // ───────────────────────────────────────────────

    describe('search', () => {
        it('does not render search input when enableSearch is false', () => {
            const element = createComponent({ enableSearch: false });
            const input = element.shadowRoot.querySelector('lightning-input[type="search"]');
            expect(input).toBeNull();
        });

        it('renders search input when enableSearch is true', () => {
            const element = createComponent({ enableSearch: true });
            const input = element.shadowRoot.querySelector('lightning-input[type="search"]');
            expect(input).not.toBeNull();
        });
    });

    // ───────────────────────────────────────────────
    //  Pagination
    // ───────────────────────────────────────────────

    describe('pagination', () => {
        it('does not show pagination when records fit in one page', async () => {
            const element = createComponent({ rowLimit: 20 });

            emitWireData(getColumnDefinitions, MOCK_COLUMNS);
            emitWireData(getRelatedRecords, { data: MOCK_RECORDS });
            await flushPromises();

            const paginationBar = element.shadowRoot.querySelector('.pagination-bar');
            expect(paginationBar).toBeNull();
        });
    });

    // ───────────────────────────────────────────────
    //  Inline Edit
    // ───────────────────────────────────────────────

    describe('inline edit', () => {
        it('does not show Save/Cancel buttons when no drafts', async () => {
            const element = createComponent({ enableInlineEdit: true });

            emitWireData(getColumnDefinitions, MOCK_COLUMNS);
            emitWireData(getRelatedRecords, { data: MOCK_RECORDS });
            await flushPromises();

            const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Save All"]');
            expect(saveBtn).toBeNull();
        });
    });

    // ───────────────────────────────────────────────
    //  New Record Button
    // ───────────────────────────────────────────────

    describe('new record', () => {
        it('does not show New button when enableNewRecord is false', () => {
            const element = createComponent({ enableNewRecord: false });
            const btn = element.shadowRoot.querySelector('lightning-button[label="New"]');
            expect(btn).toBeNull();
        });

        it('shows New button when enableNewRecord is true', () => {
            const element = createComponent({ enableNewRecord: true });
            const btn = element.shadowRoot.querySelector('lightning-button[label="New"]');
            expect(btn).not.toBeNull();
        });
    });

    // ───────────────────────────────────────────────
    //  CSV Export
    // ───────────────────────────────────────────────

    describe('csv export', () => {
        it('does not show Export button when enableExport is false', () => {
            const element = createComponent({ enableExport: false });
            const btn = element.shadowRoot.querySelector('lightning-button[label="Export CSV"]');
            expect(btn).toBeNull();
        });

        it('shows Export button when enableExport is true', () => {
            const element = createComponent({ enableExport: true });
            const btn = element.shadowRoot.querySelector('lightning-button[label="Export CSV"]');
            expect(btn).not.toBeNull();
        });
    });

    // ───────────────────────────────────────────────
    //  Color Rules — Silent Failure Fix
    // ───────────────────────────────────────────────

    describe('color rules parsing', () => {
        it('dispatches warning toast on invalid JSON', async () => {
            const toastHandler = jest.fn();
            const element = createComponent({ colorField: 'LeadSource', colorRules: '{bad json' });
            element.addEventListener(ShowToastEventName, toastHandler);

            // connectedCallback already ran, so the toast should have fired
            await flushPromises();

            expect(toastHandler).toHaveBeenCalled();
            const toastDetail = toastHandler.mock.calls[0][0].detail;
            expect(toastDetail.variant).toBe('warning');
            expect(toastDetail.title).toBe('Invalid Color Rules');
        });

        it('does not dispatch toast on valid JSON', async () => {
            const toastHandler = jest.fn();
            const element = createComponent({
                colorField: 'LeadSource',
                colorRules: '{"Hot":"red","Cold":"blue"}'
            });
            element.addEventListener(ShowToastEventName, toastHandler);

            await flushPromises();

            expect(toastHandler).not.toHaveBeenCalled();
        });
    });

    // ───────────────────────────────────────────────
    //  Error Reducer
    // ───────────────────────────────────────────────

    describe('_reduceError', () => {
        it('handles string errors', async () => {
            const element = createComponent();

            emitWireData(getColumnDefinitions, undefined, 'String error message');
            await flushPromises();

            const errorDiv = element.shadowRoot.querySelector('.slds-text-color_error');
            expect(errorDiv).not.toBeNull();
            expect(errorDiv.textContent).toBe('String error message');
        });

        it('handles error.body.message shape', async () => {
            const element = createComponent();

            emitWireData(getColumnDefinitions, undefined, { body: { message: 'Apex error' } });
            await flushPromises();

            const errorDiv = element.shadowRoot.querySelector('.slds-text-color_error');
            expect(errorDiv.textContent).toBe('Apex error');
        });
    });
});
