#include <stdio.h>
#include <stdlib.h>
#include <iostream>
using namespace std;
int main()
{

    //This is the pointer declaration for opening a file
    FILE * fp = fopen("train.txt", "r");
    FILE * wfp1 = fopen("x_data.txt", "w");
    FILE * wfp2 = fopen("y_data.txt", "w");

    double input;
    fscanf(fp, "%lf", &input);
    for (int i = 0; i < 1460; ++i) {
        fscanf(fp, "%lf", &input);
        double t = (int)(input * 10);
        int8_t temp = (int8_t)t;
        fprintf(wfp1, "%d ", temp);
    }

    // 9 & 4
    for (int i = 0; i < 20; ++i) {
        fscanf(fp, "%lf", &input);
        for (int i = 0; i < 1460; ++i) {
            fscanf(fp, "%lf", &input);
            double t = (int)(input * 10);
            int8_t temp = (int8_t)t;
            /* fprintf(wfp2, "%d ", temp); */
        }
    }

    fscanf(fp, "%lf", &input);
    for (int i = 0; i < 1460; ++i) {
        fscanf(fp, "%lf", &input);
        double t = (int)(input * 10);
        int8_t temp = (int8_t)t;
        fprintf(wfp2, "%d ", temp);
    }

   fclose(fp);

   return(0);
}
