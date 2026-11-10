import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import QUOTE_STATUS_FIELD from "@salesforce/schema/Quote.Status";
import QUOTE_TOTAL_FIELD from "@salesforce/schema/Quote.GrandTotal";
import requestPayment from "@salesforce/apex/RevenueHubPaymentRequestService.requestPayment";
import requestDocument from "@salesforce/apex/RevenueHubDocumentRequestService.requestDocument";
import getRecentJobs from "@salesforce/apex/RevenueHubMonitoringController.getRecentJobs";
import retryJob from "@salesforce/apex/RevenueHubMonitoringController.retryJob";
import canManageIntegrationJobs from "@salesforce/customPermission/Manage_Revenue_Integration_Jobs";

const QUOTE_FIELDS = [QUOTE_STATUS_FIELD, QUOTE_TOTAL_FIELD];
const JOB_COLUMNS = [
  { label: "Job", fieldName: "Name" },
  { label: "Type", fieldName: "Integration_Type__c" },
  { label: "Status", fieldName: "Status__c" },
  { label: "Attempts", fieldName: "Attempt_Count__c", type: "number" },
  { label: "Error", fieldName: "Error_Category__c" },
  { label: "Created", fieldName: "CreatedDate", type: "date" }
];

export default class RevenueHubWorkspace extends NavigationMixin(
  LightningElement
) {
  quoteId;
  quoteRecord;
  jobs = [];
  jobsError;
  quoteError;
  templateKey = "STANDARD_SALES_AGREEMENT";
  isSubmitting = false;
  isRefreshing = false;
  wiredJobsResult;

  columns = JOB_COLUMNS;
  canManageJobs = canManageIntegrationJobs;

  @wire(getRecord, { recordId: "$quoteId", fields: QUOTE_FIELDS })
  wiredQuote({ data, error }) {
    if (data) {
      this.quoteRecord = data;
      this.quoteError = undefined;
    } else if (error) {
      this.quoteRecord = undefined;
      this.quoteError = this.errorMessage(error);
    }
  }

  @wire(getRecentJobs)
  wiredJobs(result) {
    this.wiredJobsResult = result;
    if (result.data) {
      this.jobs = result.data.map((job) => ({
        ...job,
        isRetryable:
          job.Status__c === "Failed" &&
          Number(job.Attempt_Count__c) < Number(job.Maximum_Attempts__c),
        retryLabel: `Retry ${job.Name}`
      }));
      this.jobsError = undefined;
    } else if (result.error) {
      this.jobs = [];
      this.jobsError = this.errorMessage(result.error);
    }
  }

  get quoteStatus() {
    return this.quoteRecord
      ? getFieldValue(this.quoteRecord, QUOTE_STATUS_FIELD)
      : undefined;
  }

  get quoteTotal() {
    return this.quoteRecord
      ? getFieldValue(this.quoteRecord, QUOTE_TOTAL_FIELD)
      : undefined;
  }

  get isQuoteApproved() {
    return this.quoteStatus === "Approved";
  }

  get quoteStatusMessage() {
    if (!this.quoteId) {
      return "Select a Quote to review its status and request an operation.";
    }
    if (this.quoteError) {
      return this.quoteError;
    }
    if (!this.quoteRecord) {
      return "Loading Quote details...";
    }
    return this.isQuoteApproved
      ? "This Quote is approved and eligible for mock document or payment processing."
      : "Only approved Quotes can be processed.";
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get isBusy() {
    return this.isSubmitting || this.isRefreshing;
  }

  get isRequestDisabled() {
    return this.isBusy || !this.isQuoteApproved;
  }

  handleQuoteChange(event) {
    this.quoteId = event.detail.recordId;
    this.quoteRecord = undefined;
    this.quoteError = undefined;
  }

  handleTemplateChange(event) {
    this.templateKey = event.target.value;
  }

  async handlePaymentRequest() {
    await this.submitRequest(
      () => requestPayment({ quoteId: this.quoteId }),
      "Payment_Transaction__c",
      "Payment request queued"
    );
  }

  async handleDocumentRequest() {
    await this.submitRequest(
      () =>
        requestDocument({
          quoteId: this.quoteId,
          templateKey: this.templateKey
        }),
      "Document_Request__c",
      "Document request queued"
    );
  }

  async submitRequest(request, objectApiName, successTitle) {
    this.isSubmitting = true;
    try {
      const recordId = await request();
      this.dispatchEvent(
        new ShowToastEvent({
          title: successTitle,
          message: "The mock integration job is queued.",
          variant: "success"
        })
      );
      await refreshApex(this.wiredJobsResult);
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId,
          objectApiName,
          actionName: "view"
        }
      });
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to submit request",
          message: this.errorMessage(error),
          variant: "error"
        })
      );
    } finally {
      this.isSubmitting = false;
    }
  }

  async handleRefresh() {
    this.isRefreshing = true;
    try {
      await refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.jobsError = this.errorMessage(error);
    } finally {
      this.isRefreshing = false;
    }
  }

  async handleRetry(event) {
    const jobId = event.currentTarget.dataset.jobId;
    this.isSubmitting = true;
    try {
      await retryJob({ jobId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Retry queued",
          message: "The integration job has been queued for another attempt.",
          variant: "success"
        })
      );
      await refreshApex(this.wiredJobsResult);
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Unable to retry job",
          message: this.errorMessage(error),
          variant: "error"
        })
      );
    } finally {
      this.isSubmitting = false;
    }
  }

  errorMessage(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (
      error &&
      error.body &&
      Array.isArray(error.body.pageErrors) &&
      error.body.pageErrors.length
    ) {
      return error.body.pageErrors[0].message;
    }
    if (error && Array.isArray(error.body) && error.body.length) {
      return error.body[0].message;
    }
    return "An unexpected error occurred. Try again or contact your administrator.";
  }
}
