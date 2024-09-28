
#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include "./../easy_tensor.h"

void print_progress(int count, int max) {
    const int bar_width = 50;

    float progress = (float) count / max;
    int bar_length = progress * bar_width;

    printf("\rProgress: [");
    for (int i = 0; i < bar_length; ++i) {
        printf("#");
    }
    for (int i = bar_length; i < bar_width; ++i) {
        printf(" ");
    }
    printf("] %d / %d", count, max);

    fflush(stdout);
}
Tensor* copyTensorfromFILE(Tensor* dst, const char* file_name){
    char f_name[50] = "./weight/";
    int len = strlen(f_name);
    int i;
    for(i=0; file_name[i]; i++){
        f_name[i+len] = file_name[i];
    }
    f_name[i+len] = '\0';
    
    FILE *file = fopen(f_name, "rb");
    if (!file) {
        printf("Error opening file\n");
        return NULL;
    }

    size_t num_elements = fread(dst->T, sizeof(float), dst->dim[0]*dst->stride[0], file);
    if (num_elements != dst->dim[0]*dst->stride[0]) {
        printf("Error reading file\n");
        return NULL;
    }

    fclose(file);

    return dst;
}

///////////////////////////DATALOADER///////////////////////////////////
///////////////////////////DATALOADER///////////////////////////////////

FILE* LoaderINIT(const char* file_name){
    char f_name[50] = "./data/";
    int len = strlen(f_name);
    int i;
    for(i=0; file_name[i]; i++){
        f_name[i+len] = file_name[i];
    }
    f_name[i+len] = '\0';
    
    FILE *file = fopen(f_name, "rb");
    if (!file) {
        printf("Error opening file\n");
        return NULL;
    }
    return file;
}


Tensor* LoaderNEXT(Tensor* dst, FILE*file){
    if(dst->device_type){
        printf("Tensor must be on CPU\n");
        return NULL;
    }
    size_t num_elements = fread(dst->T, sizeof(float), dst->sizeTensor, file);
    if (num_elements != dst->sizeTensor) {
        printf("Error reading file\n");
        return NULL;
    }
    return dst;
}

void LoaderCLOSE(FILE* file){
    fclose(file);
}

///////////////////////////////////////////////////////////////////
/////////////////////////CrossEntropy////////////////////////////



///O->[batch_size label_len] Y->[batchsize]
float CrossEntropyLoss(Tensor* CPU_O, Tensor* CPU_Y){
    if(!CPU_O||!CPU_Y){
        printf("no Tensor.\n");
        return -1;
    }
    if(CPU_O->device_type || CPU_Y->device_type){
        printf("Tensor should be on CPU.\n");
        return -1;
    }
    if(CPU_O->dim[0] != CPU_Y->sizeTensor){
        printf("batch does not match.\n");
        return -1;
    }
    double loss = 0;
    for(int i=0; i < CPU_Y->sizeTensor;i++){
        loss -= log(CPU_O->T[CPU_O->stride[0]*i + (int)CPU_Y->T[i]]);
        
        
    }
    return loss/CPU_Y->sizeTensor;
}

__global__ void CESoftmax_deriv_(float* deriv, float* O, float* label, int O_stride, int batch_size){
    int inx = blockDim.x * blockIdx.x + threadIdx.x;//each batch
    if(inx < batch_size){
        for(int i=0; i < O_stride;i++){
            if(i == label[inx])
                deriv[O_stride * inx + i] = O[O_stride * inx + i] - 1;
            else
                deriv[O_stride * inx + i] = O[O_stride * inx + i];
        }
    }
}
Tensor* CESoftmax_deriv(Tensor* d_der_O, Tensor*d_O, Tensor* d_Y){
    if(!d_der_O || !d_O || !d_Y){
        printf("CES: no Tensor.\n");
        return NULL;
    }
    if(d_O->dim[0] != d_Y->sizeTensor){
        printf("batch does not match.\n");
        return NULL;
    }
    if(d_der_O->num_dim != d_O->num_dim){
        printf("dimention does not match.\n");
        return NULL;
    }
    cudaSetDevice(d_der_O->device_type-1);
    CESoftmax_deriv_<<<(d_der_O->dim[d_der_O->num_dim - 2] + tile_SIZE - 1)/tile_SIZE, tile_SIZE>>>(d_der_O->T,d_O->T, d_Y->T, d_der_O->dim[d_der_O->num_dim - 1], d_der_O->dim[d_der_O->num_dim - 2]);
    return d_der_O;
}


int main(){
    int batch_size = 16;
    float learning_rate = 0.0001;
    int layer_dim[] = {784, 50, 30, 40, 10};
    int in_dim[] = {batch_size, 784};

    //==========input allocation========================
    Tensor* input = mallocTensor(in_dim, 2, 0);
    Tensor* d_input = makeTensorbyShape(input, 1);
    in_dim[0] = 784;
    in_dim[1] = batch_size;
    Tensor* d_input_t = mallocTensor(in_dim, 2, 1);

    Tensor* label = mallocTensor(&batch_size, 1, 0);
    Tensor* d_label = makeTensorbyShape(label, 1);
    //==================================================

    Tensor* W[4];
    Tensor* d_W[4];
    Tensor* b[4];
    Tensor* d_b[4];

    Tensor* d_der_W[4];
    Tensor* d_W_t[4];
    Tensor* d_der_b[4];

    Tensor* d_A[4];
    Tensor* d_der_A[4];
    Tensor* d_A_t[4];
    //이건 0-9사이에 가중치만 있으므로 가능
    //==========================weight initialization===============================
    char file_name[] = "0_init_blocks.bin";
    for(int i=0; i < sizeof(W)/sizeof(Tensor*); i++){

        file_name[0] = 2*i + '0';
        W[i] = copyTensorfromFILE(mallocTensor(layer_dim+i, 2, 0), file_name);
        d_W[i] = copyTensor(makeTensorbyShape(W[i], 1), W[i]);
        d_der_W[i] = makeTensorbyShape(W[i], 1);

        in_dim[0] = layer_dim[i+1];
        in_dim[1] = layer_dim[i];
        d_W_t[i] = mallocTensor(in_dim, 2, 1);

        file_name[0] = 2*i+1 + '0';
        b[i] = copyTensorfromFILE(mallocTensor(layer_dim+i+1, 1, 0), file_name);
        d_b[i] = copyTensor(makeTensorbyShape(b[i],1),b[i]);
        d_der_b[i] = makeTensorbyShape(b[i], 1);
        
        in_dim[0] = batch_size;
        in_dim[1] = layer_dim[i+1];
        d_A[i] = mallocTensor(in_dim, 2, 1);
        d_der_A[i] = makeTensorbyShape(d_A[i], 1);

        in_dim[0] = layer_dim[i+1];
        in_dim[1] = batch_size;
        d_A_t[i] = mallocTensor(in_dim, 2, 1);
        // infoTensor(d_A_t[i]);
    }
    
    in_dim[0] = batch_size;
    in_dim[1] = layer_dim[sizeof(layer_dim)/sizeof(int)-1];
    Tensor* O = mallocTensor(in_dim, 2, 0);
    Tensor* d_O = makeTensorbyShape(O, 1);
    //===============================================================================


    //=============dataLoader========================
    FILE * data_file, *label_file;
    //===============================================
        // freeTensor(printTensor((copyTensor(makeTensorbyShape(d_W[3], 0),d_W[3]))));


    //==============================TRAIN===========================================
    for(int iter=0; iter < 1; iter++){//iteration

        data_file = LoaderINIT("data_norm.bin");
        label_file = LoaderINIT("label.bin");

        double loss = 0;
        for(int batch=0; batch < batch_size*3/batch_size;batch++){//batch
            d_input = copyTensor(d_input, LoaderNEXT(input, data_file));
            d_label = copyTensor(d_label, LoaderNEXT(label, label_file));//both label and d_label is written here.

            //forward pass
            d_A[0] = matmul_bias(d_A[0], d_input, d_W[0], d_b[0], 0);

            for(int i=1; i < sizeof(d_W)/sizeof(Tensor*);i++){
                ReLU_inline(d_A[i-1]);
                d_A[i] = matmul_bias(d_A[i], d_A[i-1], d_W[i], d_b[i], 0);
            }

            d_O = softMax(d_O, d_A[sizeof(d_A)/sizeof(Tensor*)-1]);
            loss += CrossEntropyLoss(copyTensor(O, d_O), label);//cross entropy loss
            d_der_A[sizeof(d_der_A)/sizeof(Tensor*) - 1] = CESoftmax_deriv(d_der_A[sizeof(d_der_A)/sizeof(Tensor*) - 1], d_O, d_label);
            
            // d_der_W[3] = matmul(d_der_W[3], copyTransposeTensor(d_A_t[2], d_A[2]), d_der_A[3]);
            // d_der_b[3] = rowcolwise_sum(d_der_b[3], d_A[3], 0);

            // d_der_A[2] = matmul(d_der_A[2], d_der_A[3], copyTransposeTensor(d_W_t[3], d_W[3]));
            
            // d_der_A[2] = elementWise_Tensor(d_der_A[2], d_der_A[2], 'm', d_A[2]);
            


/////////////////////////////////////////////////////////////////////////////////////////////////////
            for(int i = sizeof(d_der_W)/sizeof(Tensor*) - 1; i >=1; i--){   //3, 2, 1,
                d_der_W[i] = matmul(d_der_W[i], copyTransposeTensor(d_A_t[i-1],d_A[i-1]), d_der_A[i]);
                d_der_b[i] = rowcolwise_sum(d_der_b[i], d_A[i], 0);
                
                d_der_A[i-1] = matmul(d_der_A[i-1], d_der_A[i], copyTransposeTensor(d_W_t[i], d_W[i]));
                d_der_A[i-1] = elementWise_Tensor(d_der_A[i-1] ,d_der_A[i-1],'m', d_A[i-1]);//dReLU가 들어가야함. d_der_A[i] = d_A[i]==0 ? 0 : d_der_A[i];
            }
            
            d_der_W[0] = matmul(d_der_W[0], copyTransposeTensor(d_input_t,d_input), d_der_A[0]);
            d_der_b[0] = rowcolwise_sum(d_der_b[0], d_A[0], 0);

            
            print_progress(batch, 60000/batch_size);

            for(int i=0; i < sizeof(d_der_W)/sizeof(Tensor*); i++){
                // freeTensor(printTensor(makeSubTensor((copyTensor(makeTensorbyShape(d_W[i], 0),d_W[i])),"8 0", "8 8")));
                // freeTensor(printTensor(makeSubTensor(copyTensor(makeTensorbyShape(d_b[i], 0),d_b[i]), "0", "8")));
                d_W[i] = elementWise_Tensor(d_W[i],d_W[i],'-',scalar_Tensor(d_der_W[i], '*',learning_rate));
                d_b[i] = elementWise_Tensor(d_b[i],d_b[i],'-',scalar_Tensor(d_der_b[i], '*',learning_rate));
            }
        }
        // printTensor(label);
        // freeTensor(printTensor((copyTensor(makeTensorbyShape(d_A[sizeof(d_A)/sizeof(Tensor*)-1], 0),d_A[sizeof(d_A)/sizeof(Tensor*)-1]))));
        // freeTensor(printTensor(makeSubTensor((copyTensor(makeTensorbyShape(d_A_t[2], 0),d_A_t[2])),"8 0", "8 8")));
        // printTensor((copyTensor(makeTensorbyShape(d_A[3], 0),d_A[3])));

        // freeTensor(printTensor(makeSubTensor((copyTensor(makeTensorbyShape(d_der_A[2], 0),d_der_A[2])),"8 0", "8 8")));

        // printTensor((copyTensor(makeTensorbyShape(d_A[3], 0),d_A[3])));
        // // infoTensor(d_der_W[3]);
        // printTensor(label);

        printf("\nloss: %f\n", loss);
        printTensor(O);

        LoaderCLOSE(data_file);
        LoaderCLOSE(label_file);
        printf("\n");
    }
        //     freeTensor(printTensor((copyTensor(makeTensorbyShape(d_A[0], 0),d_A[0]))));

    
    
    

    // freeTensor(printTensor(makeSubTensor(W[3], "0 0", "8 8")));

    // // freeTensor(dW[1]);
    // for(int i=0; i < sizeof(A)/sizeof(Tensor*); i++){
    //     freeTensor(A[i]);
    // }
    

    //free Weights
    for(int i=0; i <sizeof(W)/sizeof(Tensor*);i++){
        freeTensor(W[i]);
        freeTensor(d_W[i]);
        freeTensor(d_der_W[i]);

        freeTensor(b[i]);
        freeTensor(d_b[i]);
        freeTensor(d_der_b[i]);

        freeTensor(d_A[i]);
    }
    
    

    freeTensor(d_input);
    freeTensor(input);
    

    
    
    
}