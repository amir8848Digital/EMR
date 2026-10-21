# Local patches for demo-bench

## frappe-38895-self-referential-link-alias.patch

Fixes: `MySQLdb.OperationalError: (1066, "Not unique table/alias: 'tabParameter2'")`
on list views of DocTypes with two or more self-referential Link fields
(e.g. 8848_frappe_core `Parameter`, which links to itself via `parent` and `subparent`
and has show_title_field_in_link=1).

Upstream: https://github.com/frappe/frappe/pull/38895  (backport of #38892, closes #38851)
Merged to version-16-hotfix 2026-04-25, but ABSENT from v16.52.0 / version-16 /
version-16-hotfix as of 2026-10-14. Only `develop` carries it, in refactored form
(`engine.get_link_table_alias`).

Target: apps/frappe/frappe/database/query.py  (class LinkTableField)

Reapply after any `bench update` / git pull of frappe:
    cd apps/frappe && git apply /home/amir/code/EMR/local-patches/frappe-38895-self-referential-link-alias.patch

Verify:
    LEFT JOIN `tabParameter` `tabParameter_parent`    ...
    LEFT JOIN `tabParameter` `tabParameter_subparent` ...

## 8848_frappe_core-get_total_count-v16.patch

Fixes: `ValidationError: SQL functions are not allowed as strings in SELECT:
count(distinct `tabParameter`.name) as total_count. Use dict syntax like {'COUNT': '*'} instead.`
(500 on the app's own list endpoint, e.g. /api/method/... -> document.get_list)

Cause: 8848_frappe_core/utils.py `get_total_count()` passed a raw SQL aggregate as a
*string* in `fields`. Frappe v16 rejects that (frappe/database/query.py
`_validate_select_field`). Present in v16.10.10 AND v16.52.0 — i.e. NOT a
version-jump regression; this app code is simply incompatible with frappe v16.

Fix: count over a subquery, mirroring frappe.desk.reportview.get_count — keeps
permissions + custom filters, and joins from link/child-table filters cannot
inflate the count.

Target: apps/8848_frappe_core/8848_frappe_core/utils.py

This belongs upstream in the 8848_frappe_core repo (branch master) — it is NOT
demo-specific. Raise a PR; until then reapply after any pull:
    cd apps/8848_frappe_core && git apply /home/amir/code/EMR/local-patches/8848_frappe_core-get_total_count-v16.patch
