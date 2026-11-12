// Fuzzes the libxlsx xlsx reader: ZIP container, workbook/sheet/styles/shared-strings XML,
// cell iteration, and the per-sheet metadata accessors, over an in-memory buffer.
#include <stddef.h>
#include <stdint.h>

#include "libxlsx.h"

static int count_cell(const lxlsx_cell *cell, void *ud)
{
    (*(size_t *)ud) += cell->type;
    return 0;
}

static int count_row(size_t row, size_t max_col, void *ud)
{
    (*(size_t *)ud) += row + max_col;
    return 0;
}

static void walk_styles(const lxlsx_reader_styles *st, uint32_t style_id)
{
    const lxlsx_reader_xf *xf;

    if (st == NULL)
        return;
    xf = lxlsx_reader_styles_get_xf(st, style_id);
    (void)lxlsx_reader_styles_get_font(st, style_id);
    (void)lxlsx_reader_styles_get_fill(st, style_id);
    (void)lxlsx_reader_styles_get_border(st, style_id);
    (void)xf;
}

static void walk_metadata(lxlsx_reader_worksheet *ws)
{
    size_t i, n;
    double d;
    lxlsx_reader_range range;
    lxlsx_reader_hyperlink link;
    lxlsx_reader_data_validation dv;
    lxlsx_reader_protection prot;
    lxlsx_reader_autofilter af;
    lxlsx_reader_row_options ro;
    lxlsx_reader_col_options co;

    n = lxlsx_reader_worksheet_merged_count(ws);
    for (i = 0; i < n; i++)
        (void)lxlsx_reader_worksheet_merged_get(ws, i, &range);
    n = lxlsx_reader_worksheet_hyperlink_count(ws);
    for (i = 0; i < n; i++)
        (void)lxlsx_reader_worksheet_hyperlink_get(ws, i, &link);
    n = lxlsx_reader_worksheet_data_validation_count(ws);
    for (i = 0; i < n; i++)
        (void)lxlsx_reader_worksheet_data_validation_get(ws, i, &dv);
    (void)lxlsx_reader_worksheet_protection(ws, &prot);
    (void)lxlsx_reader_worksheet_autofilter(ws, &af);
    (void)lxlsx_reader_worksheet_row_options(ws, 1, &ro);
    (void)lxlsx_reader_worksheet_col_options(ws, 1, &co);
    (void)lxlsx_reader_worksheet_default_row_height(ws, &d);
    (void)lxlsx_reader_worksheet_default_col_width(ws, &d);
    (void)lxlsx_reader_worksheet_in_merge_follow(ws, 2, 2);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    lxlsx_reader_workbook *wb = NULL;
    const lxlsx_reader_styles *st;
    size_t i, n, acc = 0;
    lxlsx_reader_defined_name dn;

    if (lxlsx_reader_workbook_open_memory(data, size, &wb) != LXLSX_READER_NO_ERROR || wb == NULL)
        return -1;

    st = lxlsx_reader_workbook_get_styles(wb);
    (void)lxlsx_reader_workbook_uses_1904_dates(wb);
    n = lxlsx_reader_workbook_defined_name_count(wb);
    for (i = 0; i < n; i++)
        (void)lxlsx_reader_workbook_defined_name_get(wb, i, &dn);

    n = lxlsx_reader_workbook_sheet_count(wb);
    for (i = 0; i < n; i++) {
        lxlsx_reader_worksheet *ws = NULL;
        lxlsx_cell cell;

        (void)lxlsx_reader_workbook_sheet_name(wb, i);
        (void)lxlsx_reader_workbook_sheet_visibility(wb, i);

        if (lxlsx_reader_workbook_get_worksheet_by_index(wb, i, LXLSX_READER_SKIP_NONE, &ws) == LXLSX_READER_NO_ERROR && ws) {
            while (lxlsx_reader_worksheet_next_row(ws) == LXLSX_READER_NO_ERROR) {
                while (lxlsx_reader_worksheet_next_cell(ws, &cell) == LXLSX_READER_NO_ERROR)
                    walk_styles(st, cell.data.reader.style_id);
            }
            walk_metadata(ws);
            lxlsx_reader_worksheet_close(ws);
        }

        ws = NULL;
        if (lxlsx_reader_workbook_get_worksheet_by_index(wb, i, LXLSX_READER_SKIP_ALL_EMPTY | LXLSX_READER_SKIP_MERGED_FOLLOW, &ws) == LXLSX_READER_NO_ERROR && ws) {
            (void)lxlsx_reader_worksheet_skip_rows(ws, 1);
            (void)lxlsx_reader_worksheet_process(ws, count_cell, count_row, &acc);
            lxlsx_reader_worksheet_close(ws);
        }
    }

    lxlsx_reader_workbook_close(wb);
    return 0;
}
