// Fuzzes the libxlsx formula parser + evaluator with an arbitrary formula string and a
// deterministic cell resolver (cell (r,c) holds r*100+c, column 3 holds a string).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "libxlsx.h"
#include "libxlsx/formula.h"

static void resolve(void *ctx, lxlsx_row_t row, lxlsx_col_t col, lxlsx_value *out)
{
    (void)ctx;
    if (col == 3) {
        out->kind = LXLSX_VAL_STRING;
        out->string = strdup("cell");
        return;
    }
    out->kind = LXLSX_VAL_NUMBER;
    out->number = (double)row * 100.0 + (double)col;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    lxlsx_value out = { LXLSX_VAL_BLANK, 0.0, NULL, LXLSX_FERR_NONE };
    char *formula = (char *)malloc(size + 1);
    lxlsx_error rc;

    if (formula == NULL)
        return -1;
    memcpy(formula, data, size);
    formula[size] = '\0';

    rc = lxlsx_formula_eval(formula, resolve, NULL, &out);
    lxlsx_value_free(&out);
    free(formula);
    return rc == LXLSX_NO_ERROR ? 0 : -1;
}
