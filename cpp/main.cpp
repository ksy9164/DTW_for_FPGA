#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

/* #define SIZE  146000 */
#define SIZE  2000
/* #define SIZE  12 */
#define X_FILE "./acsf1_data/x_data.txt"
#define Y_FILE "./acsf1_data/y_data.txt"
/* #define X_FILE "./simple_d/x_data.txt"
 * #define Y_FILE "./simple_d/y_data.txt" */

static const uint32_t x_Size = SIZE;
static const uint32_t y_Size = SIZE;
static const uint32_t w_Size = SIZE / 2;

void read_file(uint32_t *arr, FILE *fp);

union Container {
    uint8_t arr[4];
    uint32_t unioned;
};

int main(int argc, char** argv) {
    FILE * x_data_fp = fopen(X_FILE, "r");
    FILE * y_data_fp = fopen(Y_FILE, "r");
    uint32_t *x_data = NULL;
    uint32_t *y_data = NULL;

    x_data = (uint32_t *)malloc(sizeof(int8_t) * SIZE / 4);
    y_data = (uint32_t *)malloc(sizeof(int8_t) * SIZE / 4);

    read_file(x_data, x_data_fp);
    read_file(y_data, y_data_fp);

    /* get pcie instance */
    BdbmPcie* pcie = BdbmPcie::getInstance();

    int i,j;
    int x_cnt = 0;
    int y_cnt = 0;

    for (i = 0; i < SIZE / 4; ++i) {
        pcie->userWriteWord(0, x_data[i]);
        pcie->userWriteWord(4, y_data[i]);
    }
    uint32_t ans = pcie->userReadWord(0);
    sleep(1);
    printf("\nAnswer is %d ", ans);

    return 0;
}

void read_file(uint32_t *arr, FILE *fp) 
{
    int i,j;
    for (i = 0; i < SIZE / 4; ++i) {
        union Container c;
        uint8_t d = 0;
        uint32_t t_d = 0;
        for (j = 0; j < 4; j++) {
            fscanf(fp, "%d", &t_d);
            c.arr[j] = (uint8_t)t_d;
        }
        arr[i] = c.unioned;
    }
}
