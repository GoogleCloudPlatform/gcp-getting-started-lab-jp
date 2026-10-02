"""Schema + corpus loader for the policy knowledge base (idempotent).

Run inside the service's network envelope as `python -m policyapi.bootstrap`
(scripts/bootstrap-kb.sh launches it as a one-off Fargate task). Creates the
pg_trgm extension, the two tables with the generated tsvector column, and
loads the fictional corpus — re-runs truncate and reload, so the KB is always
exactly this file's content.
"""

from __future__ import annotations

import json

from . import kb

SCHEMA = (
    "CREATE EXTENSION IF NOT EXISTS pg_trgm",
    """
    CREATE TABLE IF NOT EXISTS documents (
        ref            text PRIMARY KEY,
        title          text NOT NULL,
        topic          text NOT NULL,
        owner_team     text NOT NULL,
        effective_from date NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS sections (
        doc_ref   text NOT NULL REFERENCES documents (ref) ON DELETE CASCADE,
        position  int  NOT NULL,
        heading   text NOT NULL,
        body      text NOT NULL,
        search    tsvector GENERATED ALWAYS AS
                    (to_tsvector('english', heading || ' ' || body)) STORED,
        PRIMARY KEY (doc_ref, position)
    )
    """,
    "CREATE INDEX IF NOT EXISTS sections_search_gin ON sections USING gin (search)",
    "CREATE INDEX IF NOT EXISTS sections_trgm ON sections USING gin ((heading || ' ' || body) gin_trgm_ops)",
)

# ref, title, topic, owner team, effective date, [(heading, body), ...]
CORPUS = [
    ("EXP-100", "Expense Reimbursement Policy", "finance", "Finance Operations", "2026-01-01", [
        ("Eligible expenses",
         "Employees may claim reimbursement for business meals, ground transport, and "
         "client-facing supplies. Claims are submitted in the expense portal within 30 days "
         "of the spend date; receipts are mandatory above 25 USD."),
        ("Per-diem rates",
         "Domestic travel carries a per-diem of 65 USD per day covering meals and "
         "incidentals. International travel per-diem is 95 USD per day. Per-diem replaces "
         "itemized meal claims and needs no receipts."),
        ("Approval chain",
         "Claims up to 500 USD are approved by the direct manager. Claims above 500 USD "
         "also require Finance Operations sign-off. Claims above 5000 USD go to the CFO."),
    ]),
    ("TRV-110", "Business Travel Policy", "travel", "People Team", "2026-02-15", [
        ("Booking",
         "All flights and hotels are booked through the corporate travel desk. Economy class "
         "applies to flights under six hours; premium economy is allowed beyond that."),
        ("Advance approval",
         "Trips must be approved in the travel portal at least 10 business days before "
         "departure by the cost-center owner. Emergency freight-recovery travel may be "
         "approved retroactively within 3 days."),
        ("Insurance",
         "The company carries group travel insurance for all approved trips; personal "
         "extensions of a business trip are not covered."),
    ]),
    ("SEC-200", "Information Security Access Policy", "security", "Security Office", "2025-11-01", [
        ("Access requests",
         "System access follows least privilege. Requests are raised in the access portal, "
         "require the system owner's approval, and expire after 12 months unless renewed."),
        ("Privileged accounts",
         "Privileged accounts require hardware-key MFA and quarterly re-certification by the "
         "Security Office. Shared credentials are prohibited in every system."),
        ("Access reviews",
         "Managers re-certify their reports' access each quarter. Unreviewed access is "
         "suspended automatically after the review window closes."),
    ]),
    ("HRD-210", "Onboarding and Offboarding Standard", "hr", "People Team", "2025-09-01", [
        ("Onboarding",
         "New hires receive accounts and a provisioned laptop on day one; the buddy program "
         "runs for the first six weeks."),
        ("Offboarding equipment",
         "When an employee leaves, laptops and access badges are returned on the final day. "
         "IT wipes and re-images returned laptops within 5 business days; unreturned "
         "equipment is billed to the departing employee's cost center."),
        ("Account closure",
         "All accounts are disabled at end of business on the final day, and mailbox "
         "delegation to the manager lasts 30 days."),
    ]),
    ("PRC-300", "Procurement and Purchasing Policy", "procurement", "Procurement", "2026-03-01", [
        ("Purchase orders",
         "Purchases above 1000 USD require a purchase order before the vendor is engaged. "
         "Splitting purchases to stay under the threshold is a policy violation."),
        ("Competitive quotes",
         "Purchases above 10000 USD require three competitive quotes documented in the "
         "procurement system; sole-source purchases need a written justification."),
    ]),
    ("VND-310", "Vendor Onboarding Standard", "procurement", "Procurement", "2026-03-01", [
        ("Due diligence",
         "New vendors complete a security and financial questionnaire before their first "
         "purchase order. Data-handling vendors additionally pass a Security Office review."),
        ("Contracts",
         "Only Legal-approved contract templates may be signed; side letters are void."),
    ]),
    ("ITX-400", "Acceptable Use of IT Standard", "it", "IT Services", "2025-12-01", [
        ("Devices",
         "Company laptops are managed devices; disabling the endpoint agent is prohibited. "
         "Personal devices may access mail and calendar only through the managed mobile app."),
        ("Software",
         "Software installs come from the self-service catalog. Anything else needs an IT "
         "Services exception ticket with a business justification."),
    ]),
    ("FLT-500", "Vehicle Fleet Operations Policy", "operations", "Fleet Management", "2026-04-01", [
        ("Driver eligibility",
         "Fleet vehicles are driven only by employees with a company driving clearance, "
         "renewed every two years with a license check."),
        ("Telematics",
         "All fleet vehicles run telematics; harsh-driving alerts route to the depot "
         "supervisor weekly. Telematics data is retained for 24 months."),
        ("Incidents",
         "Any collision, however minor, is reported to Fleet Management within 24 hours "
         "with photos and the counterparty details."),
    ]),
    ("WHS-510", "Warehouse Safety Standard", "operations", "Site Safety", "2026-05-01", [
        ("Protective equipment",
         "High-visibility vests and safety shoes are mandatory on the warehouse floor; "
         "visitors additionally wear helmets in racking aisles."),
        ("Forklift operations",
         "Forklifts are operated only by certified staff. Pedestrian lanes are absolute: "
         "a forklift entering a green lane is an automatic incident report."),
    ]),
    ("RET-600", "Data Retention Schedule", "security", "Legal", "2025-10-01", [
        ("Business records",
         "Financial records are retained 7 years; contracts 10 years after expiry; "
         "recruitment records of non-hired candidates 6 months."),
        ("Operational data",
         "Shipment tracking events are retained 24 months, telematics 24 months, and "
         "CCTV footage 90 days unless subject to a legal hold."),
    ]),
]


def main() -> None:
    with kb.pool().connection() as conn:
        for statement in SCHEMA:
            conn.execute(statement)
        conn.execute("TRUNCATE sections, documents")
        for ref, title, topic, owner, effective, sections in CORPUS:
            conn.execute(
                "INSERT INTO documents (ref, title, topic, owner_team, effective_from)"
                " VALUES (%s, %s, %s, %s, %s)",
                (ref, title, topic, owner, effective),
            )
            for position, (heading, body) in enumerate(sections, start=1):
                conn.execute(
                    "INSERT INTO sections (doc_ref, position, heading, body)"
                    " VALUES (%s, %s, %s, %s)",
                    (ref, position, heading, body),
                )
        counts = {
            "documents": conn.execute("SELECT count(*) AS n FROM documents").fetchone()["n"],
            "sections": conn.execute("SELECT count(*) AS n FROM sections").fetchone()["n"],
        }
    print(json.dumps({"knowledge_base": counts}))


if __name__ == "__main__":
    main()
