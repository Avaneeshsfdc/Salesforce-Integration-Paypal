import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getPaymentHistory from '@salesforce/apex/PayPalService.getPaymentHistory';

const COLUMNS = [
    {
        label: 'Transaction Number',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        }
    },
    {
        label: 'PayPal Order ID',
        fieldName: 'PayPal_Order_ID__c',
        type: 'text'
    },
    {
        label: 'Amount',
        fieldName: 'formattedAmount',
        type: 'text',
        cellAttributes: {
            class: 'amount-cell'
        }
    },
    {
        label: 'Status',
        fieldName: 'Status__c',
        type: 'text',
        cellAttributes: {
            class: { fieldName: 'statusClass' }
        }
    },
    {
        label: 'Payment Method',
        fieldName: 'Payment_Method__c',
        type: 'text'
    },
    {
        label: 'Date',
        fieldName: 'CreatedDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'View Details', name: 'view_details' },
                { label: 'View Status', name: 'view_status' }
            ]
        }
    }
];

export default class PaymentHistory extends NavigationMixin(LightningElement) {
    @api accountId;
    @api recordId;
    @track payments = [];
    @track filteredPayments = [];
    @track columns = COLUMNS;
    @track isLoading = false;
    @track error;
    @track searchTerm = '';
    @track statusFilter = 'All';
    @track sortedBy = 'CreatedDate';
    @track sortedDirection = 'desc';

    wiredPaymentsResult;

    statusOptions = [
        { label: 'All Statuses', value: 'All' },
        { label: 'Created', value: 'Created' },
        { label: 'Approved', value: 'Approved' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Cancelled', value: 'Cancelled' },
        { label: 'Failed', value: 'Failed' },
        { label: 'Refunded', value: 'Refunded' },
        { label: 'Partially Refunded', value: 'Partially Refunded' }
    ];

    @wire(getPaymentHistory, { accountId: '$effectiveAccountId' })
    wiredPayments(result) {
        this.wiredPaymentsResult = result;
        if (result.data) {
            this.payments = result.data.map(payment => ({
                ...payment,
                formattedAmount: `${payment.Currency_Code__c} ${payment.Amount__c}`,
                recordUrl: `/lightning/r/Payment_Transaction__c/${payment.Id}/view`,
                statusClass: this.getStatusClass(payment.Status__c)
            }));
            this.applyFilters();
            this.error = null;
        } else if (result.error) {
            this.error = result.error;
            this.payments = [];
            this.filteredPayments = [];
            this.showToast('Error', 'Failed to load payment history', 'error');
        }
    }

    get effectiveAccountId() {
        return this.accountId || this.recordId;
    }

    get hasPayments() {
        return this.filteredPayments && this.filteredPayments.length > 0;
    }

    get totalPayments() {
        return this.payments ? this.payments.length : 0;
    }

    get filteredCount() {
        return this.filteredPayments ? this.filteredPayments.length : 0;
    }

    get totalAmount() {
        if (!this.filteredPayments || this.filteredPayments.length === 0) {
            return 'USD 0.00';
        }
        
        const total = this.filteredPayments.reduce((sum, payment) => {
            return sum + (payment.Amount__c || 0);
        }, 0);
        
        const currency = this.filteredPayments[0]?.Currency_Code__c || 'USD';
        return `${currency} ${total.toFixed(2)}`;
    }

    getStatusClass(status) {
        switch (status) {
            case 'Completed':
                return 'slds-text-color_success';
            case 'Failed':
            case 'Cancelled':
                return 'slds-text-color_error';
            case 'Created':
            case 'Approved':
                return 'slds-text-color_warning';
            case 'Refunded':
            case 'Partially Refunded':
                return 'slds-text-color_default';
            default:
                return '';
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.applyFilters();
    }

    handleStatusFilterChange(event) {
        this.statusFilter = event.target.value;
        this.applyFilters();
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.sortData();
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'view_details':
                this.navigateToRecord(row.Id);
                break;
            case 'view_status':
                this.showPaymentStatus(row.PayPal_Order_ID__c);
                break;
        }
    }

    applyFilters() {
        let filtered = [...this.payments];

        // Apply search filter
        if (this.searchTerm) {
            const searchLower = this.searchTerm.toLowerCase();
            filtered = filtered.filter(payment => {
                return payment.Name?.toLowerCase().includes(searchLower) ||
                       payment.PayPal_Order_ID__c?.toLowerCase().includes(searchLower) ||
                       payment.Payment_Method__c?.toLowerCase().includes(searchLower);
            });
        }

        // Apply status filter
        if (this.statusFilter && this.statusFilter !== 'All') {
            filtered = filtered.filter(payment => payment.Status__c === this.statusFilter);
        }

        this.filteredPayments = filtered;
        this.sortData();
    }

    sortData() {
        const cloneData = [...this.filteredPayments];
        
        cloneData.sort((a, b) => {
            let valueA = a[this.sortedBy];
            let valueB = b[this.sortedBy];
            
            if (this.sortedBy === 'CreatedDate') {
                valueA = new Date(valueA);
                valueB = new Date(valueB);
            } else if (this.sortedBy === 'Amount__c') {
                valueA = parseFloat(valueA) || 0;
                valueB = parseFloat(valueB) || 0;
            } else {
                valueA = valueA || '';
                valueB = valueB || '';
            }
            
            if (valueA === valueB) {
                return 0;
            }
            
            let result = valueA > valueB ? 1 : -1;
            return this.sortedDirection === 'asc' ? result : -result;
        });
        
        this.filteredPayments = cloneData;
    }

    refreshData() {
        this.isLoading = true;
        return refreshApex(this.wiredPaymentsResult)
            .then(() => {
                this.showToast('Success', 'Payment history refreshed', 'success');
            })
            .catch(error => {
                console.error('Refresh error:', error);
                this.showToast('Error', 'Failed to refresh payment history', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    clearFilters() {
        this.searchTerm = '';
        this.statusFilter = 'All';
        this.applyFilters();
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    showPaymentStatus(orderId) {
        // Dispatch custom event to show payment status
        this.dispatchEvent(new CustomEvent('showpaymentstatus', {
            detail: { orderId: orderId },
            bubbles: true,
            composed: true
        }));
    }

    exportToCSV() {
        if (!this.filteredPayments || this.filteredPayments.length === 0) {
            this.showToast('Warning', 'No data to export', 'warning');
            return;
        }

        const csvHeader = 'Transaction Number,PayPal Order ID,Amount,Currency,Status,Payment Method,Created Date\n';
        const csvData = this.filteredPayments.map(payment => {
            const date = new Date(payment.CreatedDate).toLocaleDateString();
            return `"${payment.Name}","${payment.PayPal_Order_ID__c}","${payment.Amount__c}","${payment.Currency_Code__c}","${payment.Status__c}","${payment.Payment_Method__c || ''}","${date}"`;
        }).join('\n');

        const csv = csvHeader + csvData;
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        
        const link = document.createElement('a');
        link.href = url;
        link.download = `payment-history-${new Date().toISOString().split('T')[0]}.csv`;
        link.click();
        
        window.URL.revokeObjectURL(url);
        this.showToast('Success', 'Payment history exported successfully', 'success');
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
}