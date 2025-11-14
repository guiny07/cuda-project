#include <stdio.h>
#include <stdlib.h>
#include <time.h> 

// Estados possíveis
#define HEALTH 1
#define INFECTED -1
#define DEAD -2
#define EMPTY 0

void printMatrix(int **matrix, int N, int M);
int hasContaminatingNeighbor(int **matrix, int i, int j, int N, int M);

int main(int argc, char **argv)
{
    if(argc < 2)
    {
        perror("You most provide a .txt file.");
        return 1;
    }

    FILE *input = fopen(argv[1], "r");
    if(!input)
    {
        perror("Can't open file");
        return 1;
    }

    int N, M;
    fscanf(input, "%d %d", &N, &M);

    int matrix[N][M];
    int next[N][M];

    for(int i = 0; i < N; i++)
    {
        for(int j = 0; j < M; j++)
        {
            fscanf(input, "%d", &matrix[i][j]);
        }
    }
    fclose(input);

    srand(time(NULL));
    int max_iter = N * M; 
    int iter = 0;
    
    while(iter < max_iter)
    {
        int living = 0, dead = 0;
        int flag = 0; // Flag para quando uma pessoa mudou de estado (saudável, morto ou infectado).

        for(int i = 0; i < N; i++)
        {
            for(int j = 0; j < M; j++)
            {
                int current = matrix[i][j];

                if(current = HEALTH) // Se for saudável, procura por um vizinho contaminante.
                {
                    if(hasContaminatingNeighbor(matrix, i, j, N, M)) // Possui vizinho contaminante, então se torna infectado. 
                    {
                        next[i][j] = INFECTED; 
                        flag = 1;
                    }
                    else // Não possui vizinho contaminante, segue saudável. 
                        next[i][j] = HEALTH;
                }
                else if(current = INFECTED)
                {

                }
            }
        }
    }
}






int hasContaminatingNeighbor(int **matrix, int i, int j, int N, int M)
{
    /*
        Todas as direções possíveis: 
        {-1, 0} = cima;
        {1, 0} = baixo;
        {0, -1} = esquerda;
        {0, 1} = direita;
    */
    int directions[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};

    for(int d = 0; d < 4; d++)
    {
        // Calcula a posição de cada um dos 4 possíveis vizinhos. 
        int ni = i + directions[d][0];
        int nj = j + directions[d][1];

        // Verifica se o possível vizinho realmente existe. 
        if(ni >= 0 && ni < N && nj >= 0 && nj < M)
        {
            if(matrix[ni][nj] == INFECTED || matrix[ni][nj] == DEAD)
                return 1;
        }
    }

    return 0;
}