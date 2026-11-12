// Fuzzes the libxlsx edit session: opens an arbitrary xlsx (as a file in $TMPDIR, the API takes
// a path), applies a fixed set of edits across the sheet XML/styles/rels/content-types paths,
// and saves it back out.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "libxlsx.h"

static const unsigned char tiny_png[] = {
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89
};

static const char new_sheet_xml[] =
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
    "<sheetData><row r=\"1\"><c r=\"A1\"><v>1</v></c></row></sheetData></worksheet>";

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    const char *tmp = getenv("TMPDIR");
    char in_path[512], out_path[512];
    lxlsx_edit_session *s;
    FILE *f;
    int fd;
    size_t i, n;

    if (tmp == NULL || *tmp == '\0')
        tmp = "/tmp";
    snprintf(in_path, sizeof(in_path), "%s/fuzz_edit_in_XXXXXX", tmp);
    snprintf(out_path, sizeof(out_path), "%s/fuzz_edit_out_XXXXXX", tmp);

    fd = mkstemp(in_path);
    if (fd < 0)
        return -1;
    f = fdopen(fd, "wb");
    if (f == NULL) {
        close(fd);
        unlink(in_path);
        return -1;
    }
    if (size > 0 && fwrite(data, 1, size, f) != size) {
        fclose(f);
        unlink(in_path);
        return -1;
    }
    fclose(f);

    s = lxlsx_edit_open(in_path);
    if (s == NULL) {
        unlink(in_path);
        return -1;
    }

    n = lxlsx_edit_sheet_count(s);
    for (i = 0; i < n; i++)
        (void)lxlsx_edit_sheet_name(s, i);

    (void)lxlsx_edit_set_number(s, NULL, 0, 0, 42.5);
    (void)lxlsx_edit_set_string(s, NULL, 1, 1, "fuzz");
    (void)lxlsx_edit_set_boolean(s, NULL, 2, 2, 1);
    (void)lxlsx_edit_set_formula(s, NULL, 3, 3, "SUM(A1:A3)", "6");
    (void)lxlsx_edit_set_number_format(s, NULL, 0, 0, "0.00%");
    (void)lxlsx_edit_set_merge(s, NULL, 5, 0, 6, 2);
    (void)lxlsx_edit_set_column(s, NULL, 0, 2, 20.0);
    (void)lxlsx_edit_set_row_height(s, NULL, 1, 30.0);
    (void)lxlsx_edit_add_sheet(s, "FuzzSheet", new_sheet_xml, sizeof(new_sheet_xml) - 1);
    (void)lxlsx_edit_add_image(s, NULL, 8, 1, tiny_png, sizeof(tiny_png), "png", 9525, 9525, 0, 0, "px");

    fd = mkstemp(out_path);
    if (fd >= 0) {
        close(fd);
        (void)lxlsx_edit_save_as(s, out_path);
        unlink(out_path);
    }

    lxlsx_edit_close(s);
    unlink(in_path);
    return 0;
}
