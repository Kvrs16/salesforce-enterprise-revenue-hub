import { createElement } from "lwc";
import RevenueHubWorkspace from "c/revenueHubWorkspace";
import { getRecord } from "lightning/uiRecordApi";
import getRecentJobs from "@salesforce/apex/RevenueHubMonitoringController.getRecentJobs";
import requestPayment from "@salesforce/apex/RevenueHubPaymentRequestService.requestPayment";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";

jest.mock(
  "@salesforce/apex/RevenueHubPaymentRequestService.requestPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const getRecordAdapter = getRecord;
const getRecentJobsAdapter = registerApexTestWireAdapter(getRecentJobs);

const flushPromises = () => Promise.resolve().then(() => Promise.resolve());

describe("c-revenue-hub-workspace", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("keeps revenue actions disabled until an approved Quote is selected", async () => {
    const element = createElement("c-revenue-hub-workspace", {
      is: RevenueHubWorkspace
    });
    document.body.appendChild(element);
    getRecentJobsAdapter.emit([]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).toHaveLength(0);

    element.shadowRoot.querySelector("lightning-record-picker").dispatchEvent(
      new CustomEvent("change", {
        detail: { recordId: "0Q0000000000001AAA" }
      })
    );
    getRecordAdapter.emit({
      apiName: "Quote",
      id: "0Q0000000000001AAA",
      fields: {
        Status: { value: "Approved" },
        GrandTotal: { value: 250 }
      }
    });
    await flushPromises();

    const approvedButtons =
      element.shadowRoot.querySelectorAll("lightning-button");
    expect(approvedButtons[0].disabled).toBe(false);
    expect(approvedButtons[1].disabled).toBe(false);
    expect(element.shadowRoot.textContent).toContain("Approved");
  });

  it("keeps revenue actions disabled for an unapproved Quote", async () => {
    const element = createElement("c-revenue-hub-workspace", {
      is: RevenueHubWorkspace
    });
    document.body.appendChild(element);
    getRecentJobsAdapter.emit([]);

    element.shadowRoot.querySelector("lightning-record-picker").dispatchEvent(
      new CustomEvent("change", {
        detail: { recordId: "0Q0000000000002AAA" }
      })
    );
    getRecordAdapter.emit({
      apiName: "Quote",
      id: "0Q0000000000002AAA",
      fields: {
        Status: { value: "Draft" },
        GrandTotal: { value: 250 }
      }
    });
    await flushPromises();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttons[0].disabled).toBe(true);
    expect(buttons[1].disabled).toBe(true);
    expect(element.shadowRoot.textContent).toContain(
      "Only approved Quotes can be processed."
    );
  });

  it("submits a payment request for the selected approved Quote", async () => {
    const element = createElement("c-revenue-hub-workspace", {
      is: RevenueHubWorkspace
    });
    document.body.appendChild(element);
    getRecentJobsAdapter.emit([]);
    element.shadowRoot.querySelector("lightning-record-picker").dispatchEvent(
      new CustomEvent("change", {
        detail: { recordId: "0Q0000000000003AAA" }
      })
    );
    getRecordAdapter.emit({
      apiName: "Quote",
      id: "0Q0000000000003AAA",
      fields: {
        Status: { value: "Approved" },
        GrandTotal: { value: 250 }
      }
    });
    requestPayment.mockResolvedValue("a00000000000001AAA");
    await flushPromises();

    element.shadowRoot.querySelectorAll("lightning-button")[1].click();
    await flushPromises();

    expect(requestPayment).toHaveBeenCalledWith({
      quoteId: "0Q0000000000003AAA"
    });
  });
});
