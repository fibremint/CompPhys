/* heat_2d.cu
 * 2-dim. Laplace eq. (heat eq.) by finite difference with shared memory
 * Ernest Yeung  ernestyalumni@gmail.com
 * 20160625
 */
#include "heat_2d.h"

#define RAD 1 // radius of the stencil; helps to deal with "boundary conditions" at (thread) block's ends

__constant__ float dev_Deltat[1];

__constant__ float dev_heat_params[2];



int blocksNeeded( int N_i, int M_i) { return (N_i+M_i-1)/M_i; }

__device__ unsigned char clip(int n) { return n > 255 ? 255 : (n < 0 ? 0 : n);}

__device__ int idxClip( int idx, int idxMax) {
	return idx > (idxMax - 1) ? (idxMax - 1): (idx < 0 ? 0 : idx);
}

__device__ int flatten(int col, int row, int width, int height) {
	return idxClip(col, width) + idxClip(row,height)*width;
}

__global__ void resetKernel(float *d_temp, int w, int h, BC bc) {
	const int col = blockIdx.x*blockDim.x + threadIdx.x;
	const int row = blockIdx.y*blockDim.y + threadIdx.y;
	if ((col >= w) || (row >= h)) return;
	d_temp[row*w + col] = bc.t_a;
}




__global__ void tempKernel(float *d_temp, BC bc) {
	constexpr int NUS = 1;

	extern __shared__ float s_in[];
	// global indices
	const int k_x = threadIdx.x + blockDim.x * blockIdx.x;
	const int k_y = threadIdx.y + blockDim.y * blockIdx.y;
	if ((k_x >= dev_Ld[0] ) || (k_y >= dev_Ld[1] )) return;
	const int k = flatten(k_x, k_y, dev_Ld[0], dev_Ld[1]);
	// local width and height
	const int S_x = blockDim.x + 2 * RAD;
	const int S_y = blockDim.y + 2 * RAD;
	// local indices
	const int s_x = threadIdx.x + RAD;
	const int s_y = threadIdx.y + RAD;
	const int s_k = flatten(s_x, s_y, S_x, S_y);
	// assign default color values for d_out (black)

	// Load regular cells
	s_in[s_k] = d_temp[k];
	// Load halo cells
	if (threadIdx.x < RAD ) {
		s_in[flatten(s_x - RAD, s_y, S_x, S_y)] = d_temp[flatten(k_x - RAD, k_y, dev_Ld[0], dev_Ld[1])];
		s_in[flatten(s_x + blockDim.x, s_y, S_x, S_y)] = d_temp[flatten(k_x + blockDim.x, k_y, dev_Ld[0], dev_Ld[1])];
	}
	if (threadIdx.y < RAD) {
		s_in[flatten(s_x, s_y - RAD, S_x, S_y)] = d_temp[flatten(k_x, k_y - RAD, dev_Ld[0], dev_Ld[1])];
		s_in[flatten(s_x, s_y + blockDim.y, S_x, S_y)] = d_temp[flatten(k_x, k_y + blockDim.y, dev_Ld[0], dev_Ld[1])];
	}
	
	// Calculate squared distance from pipe center
	float dSq = ((k_x - bc.x)*(k_x - bc.x) + (k_y - bc.y)*(k_y - bc.y));
	// If inside pipe, set temp to t_s and return
	if (dSq < bc.rad*bc.rad) {
		d_temp[k] = bc.t_s;
		return;
	}
	// If outside plate, set temp to t_a and return
	if ((k_x == 0 ) || (k_x == dev_Ld[0] - 1) || (k_y == 0 ) ||
		(k_x + k_y < bc.chamfer) || (k_x - k_y > dev_Ld[0] - bc.chamfer)) {
			d_temp[k] = bc.t_a;
			return;
	}
	// If point is below ground, set temp to t_g and return
	if (k_y == dev_Ld[1] - 1) {
		d_temp[k] = bc.t_g;
		return;
	}
	__syncthreads();
	// For all the remaining points, find temperature.
	
	float2 stencil[NUS][2] ; 
	
	const float centerval { s_in[flatten(s_x,s_y,S_x,S_y)] };
	
	for (int nu = 0; nu < NUS; ++nu) {
		stencil[nu][0].x = s_in[flatten(s_x-(nu+1),s_y,S_x,S_y)] ; 
		stencil[nu][1].x = s_in[flatten(s_x+(nu+1),s_y,S_x,S_y)] ; 
		stencil[nu][0].y = s_in[flatten(s_x,s_y-(nu+1),S_x,S_y)] ; 
		stencil[nu][1].y = s_in[flatten(s_x,s_y+(nu+1),S_x,S_y)] ; 
	}

	float tempval { dev_lap1( centerval, stencil ) };

	float temp = 0.25f*(s_in[flatten(s_x - 1, s_y, S_x, S_y)] + 
				 s_in[flatten(s_x + 1,s_y,S_x,S_y)] + 
				 s_in[flatten(s_x, s_y - 1,S_x, S_y)] + 
				 s_in[flatten(s_x, s_y + 1, S_x, S_y)]);

//	d_temp[k] = temp;
	d_temp[k] += dev_Deltat[0]*(dev_heat_params[0]/dev_heat_params[1])*tempval;

}


__global__ void float_to_char( uchar4* dev_out, const float* outSrc) {
	const int k_x = threadIdx.x + blockDim.x * blockIdx.x;
	const int k_y = threadIdx.y + blockDim.y * blockIdx.y;
	
	const int k   = k_x + k_y * blockDim.x*gridDim.x ; 

	dev_out[k].x = 0;
	dev_out[k].z = 0;
	dev_out[k].y = 0;
	dev_out[k].w = 255;


	const unsigned char intensity = clip((int) outSrc[k] ) ;
	dev_out[k].x = intensity ;       // higher temp -> more red
	dev_out[k].z = 255 - intensity ; // lower temp -> more blue
	
}


void kernelLauncher(uchar4 *d_out, float *d_temp, int w, int h, BC bc, dim3 M_in) {
	const dim3 gridSize(blocksNeeded(w, M_in.x), blocksNeeded(h, M_in.y));
	const size_t smSz = (M_in.x + 2 * RAD)*(M_in.y + 2 * RAD)*sizeof(float);

	tempKernel<<<gridSize, M_in, smSz>>>(d_temp, bc);

	float_to_char<<<gridSize,M_in>>>(d_out, d_temp) ; 
}

void kernelLauncher2(uchar4 *d_out, float *d_temp, int w, int h, BC bc, dim3 M_in) {
	const dim3 gridSize(blocksNeeded(w, M_in.x), blocksNeeded(h, M_in.y));
	const size_t smSz = (M_in.x + 2 * RAD)*(M_in.y + 2 * RAD)*sizeof(float);

	tempKernel<<<gridSize, M_in, smSz>>>(d_temp, bc);

	float_to_char<<<gridSize,M_in>>>(d_out, d_temp) ; 
}


void resetTemperature(float *d_temp, int w, int h, BC bc, dim3 M_in) {
	const dim3 gridSize( blocksNeeded(w, M_in.x), blocksNeeded( h, M_in.y));

	resetKernel<<<gridSize, M_in>>>(d_temp,w,h,bc);
}


	
	
	
			
		
		
