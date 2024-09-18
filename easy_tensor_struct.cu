#include<stdio.h>
#include<stdlib.h>
#include<cuda_runtime.h>
#include <math.h>

#include "easy_tensor.h"
//나중에는 나눠서 각각의 gpu 안에 넣어야하기 때문에 생각을 해보면 인덱스 값에 따라 값을 copy 해주는 것도 있으면 좋을 것 같다.
//기존 텐서와 다른점. 

//1. dim과 stride가 다를 때를 고려한다. 아울러 총 크기를 그냥 저장해버린다. 이는 makelightcopysubTensor() 함수를 만들기 위함이다. 마치 커서의 드래그와 같은 역할을 해줄 것이다.(해결)
//2. num_dim이 1, 2 일때도 작동이 되도록한다.
//3. device 위에 올라가 있을 경우 dim과 stride도 같이 device에 올려준다. [5, 1, 3, 3, 4] X [4, 1, 4, 2] 와 같은 복잡한 텐서도 행렬곱이 가능하게 하기 위함이다. 



Tensor *mallocTensor(int *dim, int num_dim, int device_type){
    if(!dim){                       //if There is no dim inside
        return NULL;
    }
    if(num_dim < 0){                //if there is not an appropriate num_dim
        return NULL;
    }
    int device;
    cudaGetDeviceCount(&device);
    if(device_type > device){       //count device and check the boundary
        printf("DEVICE NUM %d NOT AVAILABLE\n", device_type);
        return NULL;
    }

    int sizeTensor;                 //check the size of whole Tensor

    Tensor* ten = (Tensor*)malloc(sizeof(Tensor));      //give tensor a space for host
    ten->dim = (int*)malloc(2 * num_dim * sizeof(int)); //give dim and stride a spcae for host
    ten->stride = ten->dim+num_dim;                    //this approach might be effective when sending to GPU later.

    ten->num_dim = num_dim;
    ten->device_type = device_type;

    sizeTensor = 1;
    for(int i= num_dim - 1; i >= 0; i--){
        ten->dim[i] = dim[i];
        ten->stride[i] = sizeTensor;
        sizeTensor *= dim[i];
    }

    ten->sizeTensor = sizeTensor;

    if(!device_type){
        ten->T = (float*)malloc(sizeTensor * sizeof(float));
        ten->d_dim_stride = NULL;
    }else{
        cudaSetDevice(device_type-1);
        cudaMalloc(&ten->T, sizeTensor * sizeof(float));
        cudaMalloc(&ten->d_dim_stride, 2 * num_dim * sizeof(int));
        cudaMemcpy(ten->d_dim_stride, ten->dim, 2 * num_dim * sizeof(int), cudaMemcpyHostToDevice);
    }
    ten->isSub = 0;
    return ten;
}

Tensor* makeTensor(const char dim[], int device_type) {  // Use `const char[]`
    int dim_[MAX_NUM_DIM];  // Array to store dimensions
    int num_dim = 0;        // Counter for the number of dimensions

    const char *ptr = dim;  // Pointer to traverse the string (now `const`)

    // Skip leading spaces
    while (*ptr == ' ') {
        ptr++;
    }

    // Parse the dimension string
    while (*ptr != '\0' && num_dim < MAX_NUM_DIM) {  // Ensure we don't exceed max dims
        // Skip spaces and commas between numbers
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }

        if (*ptr == '\0') {
            break;  // End of string
        }

        int value = 0;
        int sign = 1;

        // Optional: Handle negative numbers
        if (*ptr == '-') {
            sign = -1;
            ptr++;
        }

        // Convert digit characters to integer
        while (*ptr >= '0' && *ptr <= '9') {
            value = value * 10 + (*ptr - '0');
            ptr++;
        }

        // Store the parsed number in the dimensions array
        dim_[num_dim++] = sign * value;

        // Skip any spaces or commas after the number
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }
    }

    // If no dimensions were parsed, return NULL or handle the error appropriately
    if (num_dim == 0) {
        printf("No valid dimensions were parsed.\n");
        return NULL;
    }

    // Call makeTensor with the parsed dimensions
    return mallocTensor(dim_, num_dim, device_type);
}


Tensor* makeTensorbyShape(Tensor* src, int device_type){
    if(!src){
        printf("SouRCe is vacant.\n");
        return NULL;
    }
    // if(src->isSub){
    //     printf("Source is SubTensor.\n");
    //     return NULL;
    // }
    return mallocTensor(src->dim, src->num_dim, device_type);
}


Tensor* mallocSubTensor(Tensor* src, int* start_point, int* dim, int num_dim){
    if(src->isSub){
        printf("Cant light copy subTensor\n");
        return NULL;
    }
    if(src->num_dim < num_dim){
        printf("SouRCe num_dim not that big\n");
        return NULL;
    }

    int cont = src->num_dim - num_dim;
    float* sp = src->T;


    for(int i=0; i < src->num_dim; i++){                            //This is where you set the starting point
        if(src->dim[i] <= start_point[i]){
            printf("starting point invalid\n");
            return NULL;
        }
        sp += start_point[i] * src->stride[i];
    }

    for(int i=0; i < num_dim; i++){                                 //This is where tou check the size of the dim 
        if(src->dim[i + cont] < start_point[i+cont] + dim[i]){
            printf("SouRCe not that big.\n");
            return NULL;
        }
    }

    Tensor* subTensor = (Tensor*)malloc(sizeof(Tensor));            //Tensor malloc

    subTensor->isSub = 1;
    subTensor->device_type = src->device_type;                      //device_type same as src
    subTensor->num_dim = num_dim;                                   //num_dim

    subTensor->dim = (int*)malloc(2 * sizeof(int)* num_dim);        //dim stride malloc
    subTensor->stride = subTensor->dim + num_dim;

    subTensor->sizeTensor = 1;
    for(int i=0; i < num_dim; i++){                             
        subTensor->dim[i] = dim[i];
        subTensor-> stride[i] = src->stride[i+cont];            //copy Stride
        subTensor->sizeTensor *= dim[i];
    }

    subTensor->T = sp;

    if(src->device_type){
        cudaSetDevice(src->device_type-1);
        cudaMalloc(&subTensor->d_dim_stride, 2 * num_dim * sizeof(int));
        cudaMemcpy(subTensor->d_dim_stride, subTensor->dim, 2 * num_dim * sizeof(int), cudaMemcpyHostToDevice);
    }else{
        subTensor->d_dim_stride = NULL;
    }

    return subTensor;
}

Tensor* makeSubTensor(Tensor* src, const char start_point[], const char dim[]){

    int start_point_[MAX_NUM_DIM];  // Array to store dimensions
    int num_sp = 0;        // Counter for the number of dimensions

    const char *ptr = start_point;  // Pointer to traverse the string (now `const`)

    // Skip leading spaces
    while (*ptr == ' ') {
        ptr++;
    }

    // Parse the dimension string
    while (*ptr != '\0') {  // Ensure we don't exceed max dims
        // Skip spaces and commas between numbers
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }

        if (*ptr == '\0') {
            break;  // End of string
        }

        int value = 0;
        int sign = 1;

        // Optional: Handle negative numbers
        if (*ptr == '-') {
            sign = -1;
            ptr++;
        }

        // Convert digit characters to integer
        while (*ptr >= '0' && *ptr <= '9') {
            value = value * 10 + (*ptr - '0');
            ptr++;
        }

        // Store the parsed number in the dimensions array
        start_point_[num_sp++] = sign * value;

        // Skip any spaces or commas after the number
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }
    }

    // If no dimensions were parsed, return NULL or handle the error appropriately
    if (num_sp != src->num_dim) {
        printf("not an appropriate dimention number for starting point");
        return NULL;
    }

    ///////////////////////////////////////////////////////////////////////
    int dim_[MAX_NUM_DIM];  // Array to store dimensions
    int num_dim = 0;        // Counter for the number of dimensions

    ptr = dim;  // Pointer to traverse the string (now `const`)

    // Skip leading spaces
    while (*ptr == ' ') {
        ptr++;
    }

    // Parse the dimension string
    while (*ptr != '\0' && num_dim < MAX_NUM_DIM) {  // Ensure we don't exceed max dims
        // Skip spaces and commas between numbers
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }

        if (*ptr == '\0') {
            break;  // End of string
        }

        int value = 0;
        int sign = 1;

        // Optional: Handle negative numbers
        if (*ptr == '-') {
            sign = -1;
            ptr++;
        }

        // Convert digit characters to integer
        while (*ptr >= '0' && *ptr <= '9') {
            value = value * 10 + (*ptr - '0');
            ptr++;
        }

        // Store the parsed number in the dimensions array
        dim_[num_dim++] = sign * value;

        // Skip any spaces or commas after the number
        while (*ptr == ' ' || *ptr == ',') {
            ptr++;
        }
    }

    // If no dimensions were parsed, return NULL or handle the error appropriately
    if (num_dim == 0) {
        printf("No valid dimensions were parsed.\n");
        return NULL;
    }

    return mallocSubTensor(src, start_point_, dim_, num_dim);
}

//================================================FREEEEEEEEEEEE===============================================================

void freeSubTensor(Tensor* subTen){
    if(!subTen->isSub){
        printf("This is Not a SubTensor.\n");
        return;
    }
    if(subTen==NULL){
        printf("NO TENSOR IN POINTER.\n");
        return;
    }else{
        if(subTen->device_type){
            cudaSetDevice(subTen->device_type - 1);
            cudaError_t err = cudaFree(subTen->d_dim_stride);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA Error: %s\n", cudaGetErrorString(err));
            }
        }
        free(subTen->dim);         //didn't malloc ten->stride from the first place :P
        free(subTen);
    }
}
void freeTensor(Tensor *ten){
    if(ten==NULL){
        printf("NO TENSOR IN POINTER.\n");
        return;
    }
    if(ten->isSub){
        freeSubTensor(ten);
        return;
    }else{
        if(ten->device_type){
            cudaSetDevice(ten->device_type - 1);
            cudaError_t err = cudaFree(ten->T);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA Error: %s\n", cudaGetErrorString(err));
            }
            err = cudaFree(ten->d_dim_stride);
            if (err != cudaSuccess) {
                fprintf(stderr, "CUDA Error: %s\n", cudaGetErrorString(err));
            }
        }else{
            free(ten->T);
        }
    }
    free(ten->dim);         //didn't malloc ten->stride from the first place :P
    free(ten);
}

//=================================print================================

void infoTensor(Tensor *ten){
    printf("\n=========Tensor===========\n");
    if(ten->isSub){
        printf("===SUBTENSOR===\n");
    }
    printf("DIMENTION : [");
    for(int i=0; i < ten->num_dim-1; i++){
        printf("%d ", ten->dim[i]);
    }
    printf("%d]\n", ten->dim[ten->num_dim - 1]);
    printf("STRIDE    : [");
    for(int i=0; i < ten->num_dim-1; i++){
        printf("%d ", ten->stride[i]);
    }
    printf("%d]\n", ten->stride[ten->num_dim - 1]);
    printf("DEVICE TYPE : ");
    if(ten->device_type){
        printf("GPU %d", ten->device_type);
    }else{
        printf("CPU");
    }
    printf("\n==========================\n");
}

Tensor* printTensor(Tensor *ten){
    if(!ten){
        printf("No tensor.\n");
        return NULL;
    }
    if(ten->device_type){
        printf("printTensor : GPU mem can not be printed\n");
        return ten;
    }
    infoTensor(ten);
    //==============if ten->num_dim < 3========================
    if(ten->num_dim == 1){
        printf("[ %d ]\n", ten->dim[0]);
        for(int i=0; i < ten->dim[0]; i+=ten->stride[0]){
            printf("%.02f\t", ten->T[i]);
        }
        printf("\n");
        return ten;
    }
    if(ten->num_dim == 2){
        printf("[ %d %d ]\n", ten->dim[0], ten->dim[1]);
        for(int i=0; i < ten->dim[0]*ten->stride[0]; i+=ten->stride[0]){
            for(int j=0; j < ten->dim[1]*ten->stride[1]; j+=ten->stride[1]){
                printf("%.02f\t", ten->T[i + j]);
                // printf("%d\t", ten->stride[0]* i + j);
            }
            printf("\n");
        }
        printf("\n");
        return ten;
    }
    //=================else====================================
    printf("=\n");

    int* tmp_Inx = (int*)malloc(sizeof(int) * (ten->num_dim - 2));
    for(int i=0; i < ten->num_dim - 2; i++){
        tmp_Inx[i] = 0;
    }
    int inx;
    while(tmp_Inx[0] < ten->dim[0]){
        inx = 0;
        printf("[ ");
        for(int i=0; i < ten->num_dim-2;i++){
            printf("%d ", tmp_Inx[i]);
            inx += tmp_Inx[i] * ten->stride[i];
        }
        printf("- - ]\n");

        for(int i=0; i < ten->dim[ten->num_dim-2]*ten->stride[ten->num_dim-2]; i+=ten->stride[ten->num_dim-2]){
            for(int j=0; j < ten->dim[ten->num_dim-1]*ten->stride[ten->num_dim-1]; j+=ten->stride[ten->num_dim-1]){
                printf("%.02f\t", ten->T[inx + i + j]);
                // printf("%d\t", ten->stride[0]* i + j);
            }
            printf("\n");
        }

        tmp_Inx[ten->num_dim - 3]++;
        for(int i = ten->num_dim - 3; i > 0; i--){
            if(tmp_Inx[i] >= ten->dim[i]){
                tmp_Inx[i-1]++;
                tmp_Inx[i] = 0;
            }
        }
    }
    printf("=\n");
    free(tmp_Inx);
    return ten;
}

Tensor* copyTensor(Tensor *dst, Tensor *src){
    if(!dst || !src){
        printf("No dst or src\n");
        return NULL;
    }
    if(dst->isSub||src->isSub){
        printf("dst or src is subTensor.");
        return NULL;
    }
    if(dst->num_dim != src->num_dim){
        printf("copyMatrix : shape of dst and src doesn't match.\n");
        return NULL;
    }
    for(int i=0; i < dst->num_dim; i++){
        if(dst->dim[i] != src->dim[i]){
            printf("copyMatrix : shape of dst and src doesn't match.\n");
            return NULL;
        }
    }
    if(!dst->device_type && !src->device_type){ //CPU to CPU
        for(int i=0; i < dst->dim[0]*dst->stride[0]; i++)
            dst->T[i] = src->T[i];
    }

    else if(dst->device_type && src->device_type){
        cudaMemcpy(dst->T, src->T, dst->sizeTensor * sizeof(float), cudaMemcpyDeviceToDevice);
    }
    else if(dst->device_type){
        cudaSetDevice(dst->device_type -1);
        cudaMemcpy(dst->T, src->T, dst->sizeTensor * sizeof(float), cudaMemcpyHostToDevice);
    }else{
        cudaSetDevice(src->device_type -1);
        cudaMemcpy(dst->T, src->T, dst->sizeTensor * sizeof(float), cudaMemcpyDeviceToHost);
    }
    return dst;
}


__global__ void reshape_(float* dst, float* src, int* dst_dim_stride, int* src_dim_stride, int* reshape, int num_dim, int sizeTensor){
    src_dim_stride += num_dim;
    dst_dim_stride += num_dim;

    int new_inx = blockDim.x * blockIdx.x + threadIdx.x;
    int new_tmp = new_inx;
    int inx = 0;
    for(int i=0; i < num_dim; i++){
        inx += new_tmp / dst_dim_stride[i] * src_dim_stride[reshape[i]];
        new_tmp %= dst_dim_stride[i];
    }
    if(new_inx < sizeTensor)                            //This is for dst because tile size could go over the sizeTensor.
        dst[new_inx] = src[inx];


}


Tensor* copyReshapeTensor(Tensor* dst, Tensor* src, int* reshape){
    if(dst->isSub){
        printf("dst can't be subMatrix.\n");
        return NULL;
    }
    if(src->device_type != dst->device_type){
        printf("DEVICE NOT MATCH.\n");
        return NULL;
    }
    if(src->num_dim != dst->num_dim){
        printf("DEVICE NUM_DIM DOES NOT MATCH.\n");
        return NULL;
    }

    if(src->sizeTensor != dst->sizeTensor){
        printf("DEVICE NUM OF ELEMENT DOES NOT MATCH.\n");
        return NULL;
    }

    if(src->device_type){//GPU
        cudaSetDevice(src->device_type - 1);
        int* d_tmp_reshape;
        cudaMalloc(&d_tmp_reshape, sizeof(int) * dst->num_dim);
        cudaMemcpy(d_tmp_reshape, reshape, sizeof(int) * dst->num_dim, cudaMemcpyHostToDevice);
        
        int s_tile_SIZE = tile_SIZE * tile_SIZE * 2;//no special drawbacks in parallel sequence 임
        
        reshape_<<< (dst->sizeTensor + s_tile_SIZE - 1)/s_tile_SIZE, s_tile_SIZE >>>(dst->T, src->T, dst->d_dim_stride, src->d_dim_stride, d_tmp_reshape, src->num_dim, dst->sizeTensor);
        cudaFree(d_tmp_reshape);

    }else{//CPU
        int newInx, inx;
        for(int new_inx =0; new_inx < dst->sizeTensor; new_inx++){
            newInx = new_inx;
            inx = 0;
            for(int i=0; i < src->num_dim; i++){
                inx += newInx / dst->stride[i] * src->stride[reshape[i]];
                newInx = newInx % dst->stride[i];
            }
            dst->T[new_inx] = src->T[inx];
        }
    }

    return dst;
}


//빠르긴 한데....
__global__ void transposeCoalesced(float *odata, const float *idata, int dst_row, int dst_col, int src_col_stride, int dst_mat_stride, int src_mat_stride){
    __shared__ float tile[tile_SIZE][tile_SIZE];
    int x = blockIdx.y * tile_SIZE + threadIdx.x;  // 이건 dst를 기준으로 만든것. 일단 dim은 똑같기 때문에 조심해서 해보자. 
    int y = blockIdx.x * tile_SIZE + threadIdx.y;
    int z = blockIdx.z;
    if(x < dst_row)
        for (int j = 0; j < tile_SIZE && (y+j) < dst_col; j++)
            tile[threadIdx.x][threadIdx.y + j] = idata[z * src_mat_stride + (y+j)*src_col_stride + x];//src_row는 stride[num_dim - 2] 그리고 어차피 필요한건 다 저장이 되기 때문에 굳이 쓰레긱 값에 집중하지 말자.
    __syncthreads();
    x = blockIdx.x * tile_SIZE + threadIdx.x;
    y = blockIdx.y * tile_SIZE + threadIdx.y;

    // if(x ==8 && y==0 && z==0){
    //     for(int i=0; i < tile_SIZE; i++){
    //         for(int j=0; j < tile_SIZE; j++){
    //             printf("%.02f ", tile[i][j]);
    //         }
    //         printf("\n");
    //     }
    // }
    
    if(x < dst_col){
        for (int j = 0; j < tile_SIZE && y+j < dst_row; j++)
            odata[z * dst_mat_stride + (y+j) * dst_col + x] = tile[threadIdx.y+j][threadIdx.x];
    }
}

//////////////////////////////////////////////////////////////////////////////////

Tensor* copyTransposeTensor(Tensor* dst, Tensor* src){
    if(dst->device_type != src->device_type){
        printf("device_type does not match.\n");
        return NULL;
    }
    if(dst->num_dim <2){
        printf("dimention lesser than 2 dimention need no Transpose.\n");
        return NULL;
    }
    if(dst->num_dim != src->num_dim){
        printf("num_dim does not match.\n");
        return NULL;
    }
    
    for(int i=0; i < dst->num_dim - 2; i++){
        if(dst->dim[i] != src->dim[i]){
            printf("dimension %d does not match.\n", i);
            return NULL;
        }
    }
    if(dst->dim[dst->num_dim - 1] != src->dim[src->num_dim-2] || dst->dim[dst->num_dim - 2] != src->dim[src->num_dim-1]){
        printf("row and col does not match.\n");
        return NULL;
    }
    

    if(dst->isSub){
        printf("dst sub Matrix not allowed\n");
        return NULL;
    }
    
    if(dst->device_type){
        int dim_mat_dst;
        int dim_mat_src;
        int z;

        if(dst->num_dim == 2){
            dim_mat_dst = dst->sizeTensor;
            dim_mat_src = src->sizeTensor;
            z = 1;
        }else{
            dim_mat_dst = dst->stride[dst->num_dim - 3];
            dim_mat_src = src->stride[dst->num_dim - 3];
            z = dst->sizeTensor / dst->stride[dst->num_dim - 3];
        }
        cudaSetDevice(dst->device_type-1);
        dim3 dimGrid((dst->dim[dst->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dst->dim[dst->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, z); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
        dim3 dimBlock(tile_SIZE,1);

        transposeCoalesced<<<dimGrid, dimBlock>>>(dst->T, src->T, dst->dim[dst->num_dim - 2], dst->dim[dst->num_dim - 1], src->stride[src->num_dim - 2], dim_mat_dst, dim_mat_src);
    }else{
        if(dst->num_dim == 1){
            for(int i=0; i < dst->sizeTensor; i++){
                dst->dim[i] = src->dim[i];
            }
        }
        else if(dst->num_dim == 2){
            for(int i=0; i < dst->dim[0]; i++){
                for(int j=0; j < dst->dim[1]; j++){
                    dst->T[i*dst->dim[1] + j] = src->T[j*src->stride[0] + i];
                }
            }
        }
        else{
            
            for(int k=0; k < dst->sizeTensor / dst->stride[dst->num_dim - 3]; k++){
                for(int i=0; i < dst->dim[dst->num_dim - 2]; i++){
                    for(int j=0; j < dst->dim[dst->num_dim - 1]; j++){
                        dst->T[k * dst->stride[dst->num_dim - 3] + i * dst->stride[dst->num_dim - 2] + j] = src->T[k * src->stride[src->num_dim - 3] + j * src->stride[src->num_dim - 2] + i];
                    }
                }
            }
        }
    }
    return dst;

}

//이거 num_dim 3이상이어야 한다.
//This has to have Z dim value of C->sizeTensor / C->stride[C->num_dim - 2]
__global__ void compTiledMM_Abig(float*A, float *B, float *C, float *bias, int *dimA, int *dimB, int *dimC, int num_dim, int little_num_dim, char bias_row){
    int matIdx_A = 0, matIdx_B = 0;
    int matIdx_C = blockDim.z * blockIdx.z; //We multiply matrixDim because We have to calculate the IdxA, IdxB.
    int cont = num_dim - little_num_dim;

 int matIdx_tmp = matIdx_C * dimC[num_dim + num_dim - 3];

for(int i=0; i < cont; i++){             //To matrix(이거 그냥 가져다 쓰면 된다. 뭐 곱할 필요 없음.)
    if(dimA[i] != 1){
        matIdx_A += (matIdx_tmp/dimC[num_dim + i]) * dimA[num_dim + i];// dim inx 값을 도출하여 각각의 stride를 곱해준다. 
    }
    matIdx_tmp %= dimC[num_dim + i];
}

for(int i=cont; i < num_dim - 2; i++){      //To matrix
    if(dimA[i] != 1){
        matIdx_A += (matIdx_tmp/dimC[num_dim + i]) * dimA[num_dim + i];// dim inx 값을 도출하여 각각의 stride를 곱해준다. 
    }
    if(dimB[i-cont] != 1){
        matIdx_B += (matIdx_tmp/dimC[num_dim + i]) * dimB[little_num_dim + i-cont];
    }
    matIdx_tmp %= dimC[num_dim + i];
}
    
    int row = blockDim.y * blockIdx.y + threadIdx.y;
    int col = blockDim.x * blockIdx.x + threadIdx.x;
    __shared__ float s_a[tile_SIZE][tile_SIZE];
    __shared__ float s_b[tile_SIZE][tile_SIZE];

    float tmp = 0.0f;
    
    //output 매트릭스 stride는 그냥 dim에 맞게 해라. 그게 맞다,,,, 귀찮게 하지 말고.....

    for (int i = 0; i < (dimA[num_dim - 1] + tile_SIZE - 1) / tile_SIZE; i++) {
        //A와 B에 데이터를 넣을 때 matIdx에 차이를 두어야 한다.
        //예를 들자면 matIdx_A = blockDim.z * blockIdx.z / big_Dim_stride; 이러면 반복이 되니까.
        if (row < dimA[num_dim - 2] && (i * tile_SIZE + threadIdx.x) < dimA[num_dim - 1])
            s_a[threadIdx.y][threadIdx.x] = A[matIdx_A + row * dimA[2*num_dim - 2] + (i * tile_SIZE + threadIdx.x)];
        else 
            s_a[threadIdx.y][threadIdx.x] = 0.0f;
        

        if (col < dimB[little_num_dim-1] && (i * tile_SIZE + threadIdx.y) < dimA[num_dim-1])
            s_b[threadIdx.y][threadIdx.x] = B[matIdx_B  + (i * tile_SIZE + threadIdx.y) * dimB[2*little_num_dim - 2] + col];
        else
            s_b[threadIdx.y][threadIdx.x] = 0.0f;

        __syncthreads();

        for (int j = 0; j < tile_SIZE; j++) {
            tmp += s_a[threadIdx.y][j] * s_b[j][threadIdx.x];
        }

        __syncthreads();
    }

    // if(row==0 && col==0 && matIdx_C == 0){
    //     for(int i=0; i < tile_SIZE; i++){
    //         for(int j=0; j < tile_SIZE; j++){
    //             printf("%.02f\t", s_a[i][j]);
    //         }
    //         printf("\n");
    //     }
    //     printf("\n");
    //     for(int i=0; i < tile_SIZE; i++){
    //         for(int j=0; j < tile_SIZE; j++){
    //             printf("%.02f\t", s_b[i][j]);
    //         }
    //         printf("\n");
    //     }
    // }
    // printf("[%d %d] [%d %d]\n", row, col, dimC[num_dim - 2], dimC[num_dim-1]);
    if (row < dimC[num_dim - 2] && col < dimC[num_dim - 1]) {
        int bias_row = 0;
        if (bias)
            tmp = tmp + bias[(bias_row?row:col)];
        // printf("[%d %d %d] [%d %d] : %f\n", matIdx_C,row, col, dimC[num_dim - 2], dimC[num_dim-1], tmp);
        C[matIdx_C * dimC[2*num_dim - 3] + row * dimC[2*num_dim - 2] + col] = tmp;
    }

}

__global__ void compTiledMM_Bbig(float*A, float *B, float *C, float *bias, int *dimA, int *dimB, int *dimC, int little_num_dim, int num_dim, char bias_row){
    int matIdx_A = 0, matIdx_B = 0;
    int matIdx_C = blockDim.z * blockIdx.z; //We multiply matrixDim because We have to calculate the IdxA, IdxB.
    int cont = num_dim - little_num_dim;

 int matIdx_tmp = matIdx_C * dimC[num_dim + num_dim - 3];

for(int i=0; i < cont; i++){             //To matrix(이거 그냥 가져다 쓰면 된다. 뭐 곱할 필요 없음.)
    if(dimB[i] != 1){
        matIdx_B += (matIdx_tmp/dimC[num_dim + i]) * dimB[num_dim + i];// dim inx 값을 도출하여 각각의 stride를 곱해준다. 
    }
    matIdx_tmp %= dimC[num_dim + i];
}

for(int i=cont; i < num_dim - 2; i++){      //To matrix
    if(dimA[i-cont] != 1){
        matIdx_A += (matIdx_tmp/dimC[num_dim + i]) * dimA[little_num_dim + i-cont];// dim inx 값을 도출하여 각각의 stride를 곱해준다. 
    }
    if(dimB[i] != 1){
        matIdx_B += (matIdx_tmp/dimC[num_dim + i]) * dimB[num_dim + i];
    }
    matIdx_tmp %= dimC[num_dim + i];
}
    
    int row = blockDim.y * blockIdx.y + threadIdx.y;
    int col = blockDim.x * blockIdx.x + threadIdx.x;
    __shared__ float s_a[tile_SIZE][tile_SIZE];
    __shared__ float s_b[tile_SIZE][tile_SIZE];

    float tmp = 0.0f;
    
    //output 매트릭스 stride는 그냥 dim에 맞게 해라. 그게 맞다,,,, 귀찮게 하지 말고.....

    for (int i = 0; i < (dimA[little_num_dim - 1] + tile_SIZE - 1) / tile_SIZE; i++) {
        //A와 B에 데이터를 넣을 때 matIdx에 차이를 두어야 한다.
        //예를 들자면 matIdx_A = blockDim.z * blockIdx.z / big_Dim_stride; 이러면 반복이 되니까.
        if (row < dimA[little_num_dim - 2] && (i * tile_SIZE + threadIdx.x) < dimA[little_num_dim - 1])
            s_a[threadIdx.y][threadIdx.x] = A[matIdx_A + row * dimA[2*little_num_dim - 2] + (i * tile_SIZE + threadIdx.x)];
        else 
            s_a[threadIdx.y][threadIdx.x] = 0.0f;
        

        if (col < dimB[num_dim-1] && (i * tile_SIZE + threadIdx.y) < dimA[num_dim-1])
            s_b[threadIdx.y][threadIdx.x] = B[matIdx_B  + (i * tile_SIZE + threadIdx.y) * dimB[2*num_dim - 2] + col];
        else
            s_b[threadIdx.y][threadIdx.x] = 0.0f;

        __syncthreads();

        for (int j = 0; j < tile_SIZE; j++) {
            tmp += s_a[threadIdx.y][j] * s_b[j][threadIdx.x];
        }

        __syncthreads();
    }

    if (row < dimC[num_dim - 2] && col < dimC[num_dim - 1]) {
        if (bias)
            tmp = tmp + bias[(bias_row?row:col)];
        // printf("[%d %d %d] [%d %d] : %f\n", matIdx_C,row, col, dimC[num_dim - 2], dimC[num_dim-1], tmp);
        C[matIdx_C * dimC[2*num_dim - 3] + row * dimC[2*num_dim - 2] + col] = tmp;
    }

}

__global__ void tiledMM_Half_bigA(float *A, float *B, float *C, float *bias, int* A_dim_stride, int *B_dim_stride, int C_mat_dim, int num_dim_A, int num_dim_B, char bias_row){
    
    int row = blockDim.y * blockIdx.y + threadIdx.y;
    int col = blockDim.x * blockIdx.x + threadIdx.x;

    
    __shared__ float s_a[tile_SIZE][tile_SIZE];
    __shared__ float s_b[tile_SIZE][tile_SIZE];

    int A_matidx = blockIdx.z;
    
    float tmp = 0.0f;
    //K = A_dim_stride[A->num_dim - 1]
    //M = A_dim_stride[A->num_dim - 2]
    //N = B_dim_stride[B->num_dim - 1]
    for (int i = 0; i < (A_dim_stride[num_dim_A - 1] + tile_SIZE - 1) / tile_SIZE; i++) {
        if (row < A_dim_stride[num_dim_A - 2] && (i * tile_SIZE + threadIdx.x) < A_dim_stride[num_dim_A - 1])
        //A와 B에 데이터를 넣을 때 matIdx에 차이를 두어야 한다.
        //예를 들자면 matIdx_A = blockDim.z * blockIdx.z / big_Dim_stride; 이러면 반복이 되니까.
            s_a[threadIdx.y][threadIdx.x] = A[A_matidx * A_dim_stride[num_dim_A + num_dim_A - 3] + row * A_dim_stride[num_dim_A + num_dim_A - 2] + (i * tile_SIZE + threadIdx.x)];
        else
            s_a[threadIdx.y][threadIdx.x] = 0.0f;

        if (col < B_dim_stride[num_dim_B - 1] && (i * tile_SIZE + threadIdx.y) < A_dim_stride[num_dim_A - 1])
            s_b[threadIdx.y][threadIdx.x] = B[(i * tile_SIZE + threadIdx.y) * B_dim_stride[num_dim_B + num_dim_B - 2] + col];
        else
            s_b[threadIdx.y][threadIdx.x] = 0.0f;

        __syncthreads();
        // if(row==0 && col== 0 && A_matidx == 1){
        // }
        for (int j = 0; j < tile_SIZE; j++) {
            tmp += s_a[threadIdx.y][j] * s_b[j][threadIdx.x];
        }

        __syncthreads();
    }

    if (row < A_dim_stride[num_dim_A - 2] && col < B_dim_stride[num_dim_B - 1]) {
        if (bias)
            tmp = tmp + bias[(bias_row?row:col)];
        C[blockIdx.z * C_mat_dim + row * B_dim_stride[num_dim_B - 1] + col] = tmp;
        
    }

}




__global__ void tiledMM_Half_bigB(float *A, float *B, float *C, float *bias, int* A_dim_stride, int *B_dim_stride, int C_mat_dim, int num_dim_A, int num_dim_B, char bias_row){
    
    int row = blockDim.y * blockIdx.y + threadIdx.y;
    int col = blockDim.x * blockIdx.x + threadIdx.x;

    
    __shared__ float s_a[tile_SIZE][tile_SIZE];
    __shared__ float s_b[tile_SIZE][tile_SIZE];

    int B_matidx =  blockIdx.z;
    
    float tmp = 0.0f;
    //K = A_dim_stride[A->num_dim - 1]
    //M = A_dim_stride[A->num_dim - 2]
    //N = B_dim_stride[B->num_dim - 1]
    for (int i = 0; i < (A_dim_stride[num_dim_A - 1] + tile_SIZE - 1) / tile_SIZE; i++) {
        if (row < A_dim_stride[num_dim_A - 2] && (i * tile_SIZE + threadIdx.x) < A_dim_stride[num_dim_A - 1])
        //A와 B에 데이터를 넣을 때 matIdx에 차이를 두어야 한다.
        //예를 들자면 matIdx_A = blockDim.z * blockIdx.z / big_Dim_stride; 이러면 반복이 되니까.
            s_a[threadIdx.y][threadIdx.x] = A[row * A_dim_stride[num_dim_A + num_dim_A - 2] + (i * tile_SIZE + threadIdx.x)];
        else
            s_a[threadIdx.y][threadIdx.x] = 0.0f;

        if (col < B_dim_stride[num_dim_B - 1] && (i * tile_SIZE + threadIdx.y) < A_dim_stride[num_dim_A - 1])
            s_b[threadIdx.y][threadIdx.x] = B[B_matidx * B_dim_stride[num_dim_B + num_dim_B - 3] + (i * tile_SIZE + threadIdx.y) * B_dim_stride[num_dim_B + num_dim_B - 2] + col];
        else
            s_b[threadIdx.y][threadIdx.x] = 0.0f;

        __syncthreads();

        for (int j = 0; j < tile_SIZE; j++) {
            tmp += s_a[threadIdx.y][j] * s_b[j][threadIdx.x];
        }

        __syncthreads();
    }

    if (row < A_dim_stride[num_dim_A - 2] && col < B_dim_stride[num_dim_B - 1]) {
        if (bias)
            tmp = tmp + bias[(bias_row?row:col)];
        C[blockIdx.z * C_mat_dim + row * B_dim_stride[num_dim_B - 1] + col] = tmp;
    }

}



__global__ void tiledMM_2d(float *A, float *B, float *C, float *bias, int M, int N, int K, int A_stride, int B_stride, char bias_row) {    
    
    int row = blockDim.y * blockIdx.y + threadIdx.y;
    int col = blockDim.x * blockIdx.x + threadIdx.x;
    __shared__ float s_a[tile_SIZE][tile_SIZE];
    __shared__ float s_b[tile_SIZE][tile_SIZE];

    float tmp = 0.0f;

    for (int i = 0; i < (K + tile_SIZE - 1) / tile_SIZE; i++) {
        if (row < M && (i * tile_SIZE + threadIdx.x) < K)
        //A와 B에 데이터를 넣을 때 matIdx에 차이를 두어야 한다.
        //예를 들자면 matIdx_A = blockDim.z * blockIdx.z / big_Dim_stride; 이러면 반복이 되니까.
            s_a[threadIdx.y][threadIdx.x] = A[row * A_stride + (i * tile_SIZE + threadIdx.x)];
        else
            s_a[threadIdx.y][threadIdx.x] = 0.0f;

        if (col < N && (i * tile_SIZE + threadIdx.y) < K)
            s_b[threadIdx.y][threadIdx.x] = B[(i * tile_SIZE + threadIdx.y) * B_stride + col];
        else
            s_b[threadIdx.y][threadIdx.x] = 0.0f;

        __syncthreads();

        for (int j = 0; j < tile_SIZE; j++) {
            tmp += s_a[threadIdx.y][j] * s_b[j][threadIdx.x];
        }

        __syncthreads();

    }

    if (row < M && col < N) {
        if (bias)
            tmp = tmp + bias[(bias_row?row:col)];
        C[row * N + col] = tmp;
    }
}

__global__ void checkmem(float* arr, int len){
    for(int i=0; i < len; i++){
        printf("%f ", arr[i]);
    }
    printf("\n");
}

Tensor* matmul(Tensor* dC, Tensor* dA, Tensor* dB){
    if(!dC||!dB||!dA){
        printf("one of Tensor is NULL.\n");
        return NULL;
    }
    if(dC->isSub){
        printf("The result Matrix can not be a sub Matrix.\n");
        return NULL;
    }
    if(dC->device_type != dB->device_type || dB->device_type != dA->device_type){
        printf("Three matrices are in different device.");
        return NULL;
    }

    
    if(dC->num_dim <2 || dB->num_dim <2 || dA->num_dim <2){
        printf("One of three Tensor has less than 2 dimentions.(Try to use matmul().)\n");
        return NULL;
    }
    

    //2. matrix col and row has to be the same.
    if(dA->dim[dA->num_dim - 1] != dB->dim[dB->num_dim - 2]){
        printf("tensor's row and column does not match.(%d %d)\n", dA->dim[dA->num_dim - 1], dB->dim[dB->num_dim - 2]);
        return NULL;
    }

    if(dA->dim[dA->num_dim - 2] != dC->dim[dC->num_dim - 2] || dB->dim[dB->num_dim - 1] != dC->dim[dC->num_dim - 1]){
        printf("tensor's row and column does not match.\n");
        return NULL;
    }
    
    Tensor* bigTensor, *smallTensor;

    if(dA->num_dim >= dB->num_dim){
        bigTensor = dA;
        smallTensor = dB;
    }else{
        bigTensor = dB;
        smallTensor = dA;
    }


    if(bigTensor->num_dim != dC->num_dim){
        printf("dC num_dim has to have same num_dim as bigger Tensor.\n");
        return NULL;
    }

    if(bigTensor->num_dim ==2){
        cudaSetDevice(bigTensor->device_type-1);
        dim3 dimGrid((dB->dim[dB->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dA->dim[dA->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, 1); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
        dim3 dimBlock(tile_SIZE, tile_SIZE);
        tiledMM_2d<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, NULL, dA->dim[0], dB->dim[1], dA->dim[1], dA->stride[0], dB->stride[0], 0);
    
    }
    else{
        //num_dim이 모두 2보다 클 때
        for(int i=0; i < bigTensor->num_dim - 2; i++){
            if(bigTensor->dim[i] != dC->dim[i] && bigTensor->dim[i] != 1){
                printf("%d dimention of Tensor(big) does not Match.\n", i);
                return NULL;
            }
        }
        
        if(smallTensor->num_dim == 2){

            cudaSetDevice(dA->device_type - 1);
            dim3 dimGrid((dC->dim[dC->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dC->dim[dC->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, dC->sizeTensor / dC->stride[bigTensor->num_dim - 3]); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
            dim3 dimBlock(tile_SIZE, tile_SIZE);
            if(dA == bigTensor)
                tiledMM_Half_bigA<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, NULL, dA->d_dim_stride, dB->d_dim_stride, dC->stride[dC->num_dim - 3], dA->num_dim, dB->num_dim, 0);
            else
                tiledMM_Half_bigB<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, NULL, dA->d_dim_stride, dB->d_dim_stride, dC->stride[dC->num_dim - 3], dA->num_dim, dB->num_dim, 0);

        }else{

            int cont = bigTensor->num_dim - smallTensor->num_dim;

            //1. The tensor has to match if one of them is not 1.
            for(int i=0; i < smallTensor->num_dim - 2; i++){
                if(smallTensor->dim[i] != dC->dim[i+cont] && smallTensor->dim[i] != 1){
                    printf("%d dimention of Tensor(small) does not Match.\n", i);
                    return NULL;
                }
            }

            cudaSetDevice(dA->device_type - 1);
            dim3 dimGrid((dC->dim[dC->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dC->dim[dC->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, dC->sizeTensor / dC->stride[dC->num_dim - 3]); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
            dim3 dimBlock(tile_SIZE, tile_SIZE);
            if(dA == bigTensor)
                compTiledMM_Abig<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, NULL, dA->d_dim_stride, dB->d_dim_stride, dC->d_dim_stride, dA->num_dim, dB->num_dim, 0);
            else
                compTiledMM_Bbig<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, NULL, dA->d_dim_stride, dB->d_dim_stride, dC->d_dim_stride, dA->num_dim, dB->num_dim, 0);
            
        }
        
    }
    
    return dC;
    
    //if [5, 1, 3, 4, 5] x [4, 1, 5, 4]
    

}


Tensor* matmul_bias(Tensor* dC, Tensor* dA, Tensor* dB, Tensor* dbias, char row_bias){
    if(!dC||!dB||!dA||!dbias){
        printf("one of Tensor is NULL.\n");
        return NULL;
    }
    if(dC->isSub){
        printf("The result Matrix can not be a sub Matrix.\n");
        return NULL;
    }
    if(dC->device_type != dB->device_type || dB->device_type != dA->device_type || dbias->device_type != dA->device_type){
        printf("Four matrices are in different device.");
        return NULL;
    }

    
    if(dC->num_dim <2 || dB->num_dim <2 || dA->num_dim <2){
        printf("One of three Tensor has less than 2 dimentions.(Try to use matmul().)\n");
        return NULL;
    }
    
    if(dbias->num_dim != 1){
        if(dbias->num_dim != 2 || dbias->dim[1] != dC->dim[dC->num_dim - 1]){
            printf("bias not an appropriate dimention.\n");
            return NULL;
        }
    }

    if(dbias->dim[dbias->num_dim - 1] != dB->dim[dB->num_dim - 1]){
        printf("Bias size does not fit to column(dB's last dim).\n");
        return NULL;
    }

    //2. matrix col and row has to be the same.
    if(dA->dim[dA->num_dim - 1] != dB->dim[dB->num_dim - 2]){
        printf("tensor's row and column does not match.(%d %d)\n", dA->dim[dA->num_dim - 1], dB->dim[dB->num_dim - 2]);
        return NULL;
    }

    if(dA->dim[dA->num_dim - 2] != dC->dim[dC->num_dim - 2] || dB->dim[dB->num_dim - 1] != dC->dim[dC->num_dim - 1]){
        printf("tensor's row and column does not match.\n");
        return NULL;
    }
    
    Tensor* bigTensor, *smallTensor;

    if(dA->num_dim >= dB->num_dim){
        bigTensor = dA;
        smallTensor = dB;
    }else{
        bigTensor = dB;
        smallTensor = dA;
    }


    if(bigTensor->num_dim != dC->num_dim){
        printf("dC num_dim has to have same num_dim as bigger Tensor.\n");
        return NULL;
    }

    if(bigTensor->num_dim ==2){
        cudaSetDevice(bigTensor->device_type-1);
        dim3 dimGrid((dB->dim[dB->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dA->dim[dA->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, 1); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
        dim3 dimBlock(tile_SIZE, tile_SIZE);
        tiledMM_2d<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, dbias->T, dA->dim[0], dB->dim[1], dA->dim[1], dA->stride[0], dB->stride[0], row_bias);
    
    }
    else{
        //num_dim이 모두 2보다 클 때
        for(int i=0; i < bigTensor->num_dim - 2; i++){
            if(bigTensor->dim[i] != dC->dim[i] && bigTensor->dim[i] != 1){
                printf("%d dimention of Tensor(big) does not Match.\n", i);
                return NULL;
            }
        }
        
        if(smallTensor->num_dim == 2){

            cudaSetDevice(dA->device_type - 1);
            dim3 dimGrid((dC->dim[dC->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dC->dim[dC->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, dC->sizeTensor / dC->stride[bigTensor->num_dim - 3]); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
            dim3 dimBlock(tile_SIZE, tile_SIZE);
            if(dA == bigTensor)
                tiledMM_Half_bigA<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, dbias->T, dA->d_dim_stride, dB->d_dim_stride, dC->stride[dC->num_dim - 3], dA->num_dim, dB->num_dim, row_bias);
            else
                tiledMM_Half_bigB<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, dbias->T, dA->d_dim_stride, dB->d_dim_stride, dC->stride[dC->num_dim - 3], dA->num_dim, dB->num_dim, row_bias);

        }else{

            int cont = bigTensor->num_dim - smallTensor->num_dim;

            //1. The tensor has to match if one of them is not 1.
            for(int i=0; i < smallTensor->num_dim - 2; i++){
                if(smallTensor->dim[i] != dC->dim[i+cont] && smallTensor->dim[i] != 1){
                    printf("%d dimention of Tensor(small) does not Match.\n", i);
                    return NULL;
                }
            }

            cudaSetDevice(dA->device_type - 1);
            dim3 dimGrid((dC->dim[dC->num_dim - 1] + tile_SIZE - 1) / tile_SIZE, (dC->dim[dC->num_dim - 2] + tile_SIZE - 1) / tile_SIZE, dC->sizeTensor / dC->stride[dC->num_dim - 3]); //dim은 4x3x32x32를 matmul하는 경우 12가 들어가게 된다.
            dim3 dimBlock(tile_SIZE, tile_SIZE);
            if(dA == bigTensor)
                compTiledMM_Abig<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, dbias->T, dA->d_dim_stride, dB->d_dim_stride, dC->d_dim_stride, dA->num_dim, dB->num_dim, row_bias);
            else
                compTiledMM_Bbig<<<dimGrid, dimBlock>>>(dA->T, dB->T, dC->T, dbias->T, dA->d_dim_stride, dB->d_dim_stride, dC->d_dim_stride, dA->num_dim, dB->num_dim, row_bias);
            
        }
        
    }
    return dC;
    
    //if [5, 1, 3, 4, 5] x [4, 1, 5, 4]
    

}










__global__ void ReLU(float* T, int sizeTensor){
    int inx = blockIdx.x * blockDim.x + threadIdx.x;
    if(inx < sizeTensor)
        T[inx] = (T[inx] >=0) ? T[inx] : 0;
}


Tensor* ReLU_inline(Tensor* ten){
    if(!ten){
        printf("No Tensor.\n");
        return NULL;
    }
    if(ten->device_type){
        cudaSetDevice(ten->device_type - 1);
        ReLU<<<(ten->sizeTensor+tile_SIZE-1)/tile_SIZE, tile_SIZE*tile_SIZE>>>(ten->T, ten->sizeTensor);
    }else{
        for(int i=0; i < ten->sizeTensor; i++){
            ten->T[i] = (ten->T[i] >=0) ? ten->T[i] : 0;
        }
        
    }
    return ten;
}

__global__ void gelu_(float* in, float* out, int len) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if (i < len) {  
        // Do the actual computation
        out[i] = 0.5 * in[i] * (1.0 + tanh(0.79788456 * (in[i] + 0.044715 * in[i] * in[i] * in[i])));
    }
}


// __global__ void sub_(float* dC, float* dA, float* dB, int len){
//     int inx = blockDim.x * blockIdx.x + threadIdx.x;
// }

// Tensor* subtract_Tensor(Tensor* dC, Tensor* dB, Tensor* dA){
//     if(!dC || !dA || !dB){
//         printf("no Tensor\n");
//         return NULL;
//     }
//     if(dC->device_type != dB->device_type && dB->device_type != dA->device_type){
//         printf("Device type does not match\n");
//         return NULL;
//     }
    
//     if(dC->num_dim != dB->num_dim || dC->num_dim != dA->num_dim){
//         printf("Number of dim does not match.\n");
//         return NULL;
//     }
//     for(int i=0; i < dC->num_dim; i++){
//         if(dC->dim[i] != dB[i] || dC->dim[i] != dA->dim[i]){
//             printf("dimention does not match.\n");
//             return NULL;
//         }
//     }

//     if(dC->device_type){

//     }else{

//     }
//     return dC;
// }