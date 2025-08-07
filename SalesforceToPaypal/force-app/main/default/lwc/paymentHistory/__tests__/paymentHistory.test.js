import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import PaymentHistory from 'c/paymentHistory';
import getPaymentHistory from '@salesforce/apex/PayPalService.getPaymentHistory';
import getPaymentStats from '@salesforce/apex/PaymentProcessor.getPaymentStats';

// Mock the wire adapters and Apex methods
jest.mock(
    'lightning/uiRecordApi',
    () => {
        const { createLdsTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            getRecord: createLdsTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/PayPalService.getPaymentHistory',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/PaymentProcessor.getPaymentStats',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

// Mock data
const mockPaymentHistory = [
    {
        Id: '001',
        Amount__c: 100.00,
        Currency__c: 'USD',
        Status__c: 'Completed',
        Description__c: 'Test Payment 1',
        PayPal_Order_ID__c: 'ORDER123',
        CreatedDate: '2024-01-01T00:00:00Z',
        Payment_Date__c: '2024-01-01T00:00:00Z'
    },
    {
        Id: '002',
        Amount__c: 50.00,
        Currency__c: 'USD',
        Status__c: 'Pending',
        Description__c: 'Test Payment 2',
        PayPal_Order_ID__c: 'ORDER456',
        CreatedDate: '2024-01-02T00:00:00Z',
        Payment_Date__c: '2024-01-02T00:00:00Z'
    }
];

const mockPaymentStats = {
    totalTransactions: 2,
    totalAmount: 150.00,
    statusBreakdown: {
        'Completed': 1,
        'Pending': 1
    },
    currencyBreakdown: {
        'USD': 150.00
    }
};

describe('c-payment-history', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders payment history table with data', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        expect(dataTable).toBeTruthy();
        expect(dataTable.data).toEqual(mockPaymentHistory);
    });

    it('displays payment stats summary', async () => {
        getPaymentStats.emit(mockPaymentStats);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const totalTransactions = element.shadowRoot.querySelector('[data-id="total-transactions"]');
        const totalAmount = element.shadowRoot.querySelector('[data-id="total-amount"]');
        
        expect(totalTransactions.textContent).toContain('2');
        expect(totalAmount.textContent).toContain('$150.00');
    });

    it('handles empty payment history gracefully', async () => {
        getPaymentHistory.emit([]);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const emptyMessage = element.shadowRoot.querySelector('.empty-state');
        expect(emptyMessage).toBeTruthy();
        expect(emptyMessage.textContent).toContain('No payment history');
    });

    it('shows loading spinner while data loads', () => {
        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    it('handles error loading payment history', async () => {
        getPaymentHistory.error({ body: { message: 'Failed to load payment history' } });

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('Failed to load');
    });

    it('filters payments by status', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        // Select status filter
        const statusFilter = element.shadowRoot.querySelector('[data-id="status-filter"]');
        statusFilter.value = 'Completed';
        statusFilter.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        const filteredData = dataTable.data;
        
        expect(filteredData.length).toBe(1);
        expect(filteredData[0].Status__c).toBe('Completed');
    });

    it('filters payments by date range', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        // Set date filters
        const startDateInput = element.shadowRoot.querySelector('[data-id="start-date"]');
        const endDateInput = element.shadowRoot.querySelector('[data-id="end-date"]');
        
        startDateInput.value = '2024-01-01';
        startDateInput.dispatchEvent(new CustomEvent('change'));
        
        endDateInput.value = '2024-01-01';
        endDateInput.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        const filteredData = dataTable.data;
        
        expect(filteredData.length).toBe(1);
        expect(filteredData[0].Id).toBe('001');
    });

    it('sorts payments by column', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        
        // Simulate column sort
        dataTable.dispatchEvent(new CustomEvent('sort', {
            detail: {
                fieldName: 'Amount__c',
                sortDirection: 'desc'
            }
        }));

        await Promise.resolve();

        const sortedData = dataTable.data;
        expect(sortedData[0].Amount__c).toBe(100.00);
        expect(sortedData[1].Amount__c).toBe(50.00);
    });

    it('exports payment history to CSV', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        // Mock URL.createObjectURL
        global.URL.createObjectURL = jest.fn(() => 'mock-url');
        global.URL.revokeObjectURL = jest.fn();

        const exportButton = element.shadowRoot.querySelector('[data-id="export-btn"]');
        exportButton.click();

        await Promise.resolve();

        expect(global.URL.createObjectURL).toHaveBeenCalled();
    });

    it('refreshes payment history data', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const refreshButton = element.shadowRoot.querySelector('[data-id="refresh-btn"]');
        refreshButton.click();

        await Promise.resolve();

        // Verify refresh was triggered (implementation dependent)
        expect(getPaymentHistory).toHaveBeenCalled();
    });

    it('displays status breakdown chart', async () => {
        getPaymentStats.emit(mockPaymentStats);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const statusChart = element.shadowRoot.querySelector('.status-chart');
        expect(statusChart).toBeTruthy();
    });

    it('displays currency breakdown', async () => {
        getPaymentStats.emit(mockPaymentStats);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const currencyBreakdown = element.shadowRoot.querySelector('.currency-breakdown');
        expect(currencyBreakdown).toBeTruthy();
        expect(currencyBreakdown.textContent).toContain('USD: $150.00');
    });

    it('handles row actions on payment records', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        
        // Simulate row action
        dataTable.dispatchEvent(new CustomEvent('rowaction', {
            detail: {
                action: { name: 'view_details' },
                row: mockPaymentHistory[0]
            }
        }));

        await Promise.resolve();

        // Verify action was handled (implementation dependent)
        const modal = element.shadowRoot.querySelector('.payment-details-modal');
        expect(modal).toBeTruthy();
    });

    it('paginates large payment history', async () => {
        // Create large dataset
        const largeDataset = Array.from({ length: 50 }, (_, i) => ({
            Id: `00${i}`,
            Amount__c: 100.00 + i,
            Currency__c: 'USD',
            Status__c: 'Completed',
            Description__c: `Test Payment ${i}`,
            PayPal_Order_ID__c: `ORDER${i}`,
            CreatedDate: '2024-01-01T00:00:00Z'
        }));

        getPaymentHistory.emit(largeDataset);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const pagination = element.shadowRoot.querySelector('.pagination-controls');
        expect(pagination).toBeTruthy();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        expect(dataTable.data.length).toBeLessThanOrEqual(25); // Default page size
    });

    it('shows payment details modal', async () => {
        getPaymentHistory.emit(mockPaymentHistory);

        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        element.recordId = '0031234567890ABC';
        document.body.appendChild(element);

        await Promise.resolve();

        const dataTable = element.shadowRoot.querySelector('lightning-datatable');
        
        // Simulate view details action
        dataTable.dispatchEvent(new CustomEvent('rowaction', {
            detail: {
                action: { name: 'view_details' },
                row: mockPaymentHistory[0]
            }
        }));

        await Promise.resolve();

        const modal = element.shadowRoot.querySelector('.payment-details-modal');
        const modalTitle = element.shadowRoot.querySelector('.modal-title');
        
        expect(modal).toBeTruthy();
        expect(modalTitle.textContent).toContain('Payment Details');
    });

    it('closes payment details modal', async () => {
        const element = createElement('c-payment-history', {
            is: PaymentHistory
        });
        document.body.appendChild(element);

        // Open modal first
        element.selectedPayment = mockPaymentHistory[0];
        element.showPaymentDetails = true;

        await Promise.resolve();

        const closeButton = element.shadowRoot.querySelector('[data-id="close-modal-btn"]');
        closeButton.click();

        await Promise.resolve();

        const modal = element.shadowRoot.querySelector('.payment-details-modal');
        expect(modal).toBeFalsy();
    });
});