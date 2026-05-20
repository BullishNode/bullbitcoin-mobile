# Bullnym Architecture

This feature owns the Bullnym HTTP protocol client, DTOs, signing helpers, and
shared constants used by Lightning Address, Payment Page, and Invoices.

It is neutral protocol infrastructure. Get Paid and Lightning Address may
depend on it, but it must not depend on either feature.
