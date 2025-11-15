#include <stdio.h>
#include <stdlib.h> 
#include <time.h>

/*
    Código script para gerar matrizes 2000x2000 para os testes de CPU x GPU.
*/

#define HEALTH 1 
#define INFECTED -1 
#define DEAD -2 
#define EMPTY 0 

int main(int argc, char **argv)
{
    if(argc < 4)
    {
        printf("Please, use: %s N M filename.txt", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]);
    int M = atoi(argv[2]);
    const char *filename = argv[3];

    FILE *f = fopen(filename, "w");
    if(!f)
    {
        perror("Can't open file.");
        return 1;
    }

    srand(time(NULL));

    // Header do .txt
    fprintf(f, "%d %d\n", N, M);

    /*
        Distribuição aplicada: 

        HEALTH (1):  80%
        INFECTED (-1): 8%
        DEAD (-2): 2%
        EMPTY (0): 10%

        Pode ser ajustado se precisar...
    */

    for(int i = 0; i < N; i++)
    {
        for(int j = 0; j < M; j++)
        {
            int random = rand() % 100;

            int value;
            if(random < 80) value = HEALTH;
            else if(random < 88) value = INFECTED;
            else if(random < 90) value = DEAD;
            else value = EMPTY; 

            fprintf(f, "%d", value);
            if(j < M - 1) fprintf(f, " ");
        }
        fprintf(f, "\n");
    }

    fclose(f);

    printf("File '%s' generated successfully (%dx%d).", filename, N, M);
    return 0;
}