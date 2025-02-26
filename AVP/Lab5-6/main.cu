#include <iostream>

#define THREAD_PER_BLOCK_X  32
#define THREAD_PER_BLOCK_Y  32

#define MATRIX_BLOCK_WIDTH (1024 * 16)
#define MATRIX_BLOCK_HEIGHT (1024 * 16)

#include <iostream>
#include <chrono>
#include <utility>

#include "helper_image.h"

#include "grey.cuh"
#include "RGB.cuh"

#include "cuda_runtime.h"
#include "device_launch_parameters.h"


template<typename F, typename... Args>
double measureTime(F func, Args&&... args);
void CmpResult(unsigned char* a, unsigned char* b, int size, const std::string& a_string, const std::string& b_string);
void Host_Filter(unsigned char* data, unsigned char* res, unsigned int w, unsigned int h, int channels);


template<typename F, typename... Args>
double measureTime(F func, Args&&... args) {
#define duration(a) std::chrono::duration_cast<std::chrono::microseconds>(a).count()
#define timeNow() std::chrono::high_resolution_clock::now()
    typedef std::chrono::high_resolution_clock::time_point TimeVar;
    TimeVar t1 = timeNow();
    func(std::forward<Args>(args)...);
    TimeVar t2 = timeNow();
    return duration(t2 - t1) / 1000.;
}

void tobin(unsigned char a)
{
    char bin[8];
    for (int i = 0; i < 8; i++)
    {
        bin[i] = a & (1 << (7 - i));
    }
    for(int i = 0; i < 8 ; i++)
    {
        std::cout << (bool)bin[i];

    }
}

void CmpResult(unsigned char* a, unsigned char* b, int size, const std::string& a_string, const std::string& b_string) {
    int cmp_val = memcmp(a, b, size);
    std::cout << a_string << " ";
    if (cmp_val == 0) {
        std::cout << "==";
    }
    else {
        std::cout << "!=";
    }
    std::cout << " " << b_string << '\n';
}


void Host_Filter(unsigned char* data, unsigned char* res, unsigned int width, unsigned int height, int channel)
{
    for (int i = 0; i < height; i++)
    {
        unsigned char* curLine = data + i * width * channel;
        unsigned char* nextLine = data + (i + 1) * width * channel;
        unsigned char* prevLine = data + (i - 1) * width * channel;
        unsigned char* resLine = res + i * width * channel;
        for (int j = 0; j < width * channel; j++)
        {
            int pixel = 0;
            if (i == 0 || i == height - 1) // первая / последняя строчка
            {
                if (i == 0) // первая
                {
                    if (j - channel < 0)    // первый пиксель (+)
                    {
                        pixel = -3 * curLine[j] + 9 * curLine[j] - 2 * curLine[j + channel]
                                - 2 * nextLine[j] - nextLine[j + channel];
                    }
                    if (j + channel >= width * channel) // последний пиксель первой строки (+)
                    {
                        pixel = -2 * curLine[j - channel] - 3 * curLine[j] + 9 * curLine[j]
                                - nextLine[j - channel] - 2 * nextLine[j];
                    }
                    if (j - channel >= 0 && j + channel < width * channel)  // между первым и последним (+)
                    {
                        pixel = -2 * curLine[j - channel] - curLine[j] + 9 * curLine[j] - 2 * curLine[j + channel]
                                - nextLine[j - channel] - nextLine[j] - nextLine[j + channel];
                    }
                }
                if (i == height - 1)    // последняя
                {
                    if (j - channel < 0)    //крайний левый пиксель (+)
                    {
                        pixel = -2 * prevLine[j] - prevLine[j + channel]
                                + 9 * curLine[j] - 3 * curLine[j] - 2 * curLine[j + channel];
                    }
                    if (j + channel >= width * channel) // крайний правый пиксель (+)
                    {
                        pixel = - prevLine[j - channel] - 2 * prevLine[j]
                                - 2 * curLine[j - channel] + 9 * curLine[j] - 3 * curLine[j];
                    }
                    if (j - channel >= 0 && j + channel < width * channel)  // между крайними (+)
                    {
                        pixel = - prevLine[j - channel] - prevLine[j] - prevLine[j + channel]
                                - 2 * curLine[j - channel] + 9 * curLine[j] - curLine[j] - 2 * curLine[j + channel];
                    }
                }
            } else
            {
                if (j - channel < 0)    // первый столбец (+)
                {
                    pixel = -2 * prevLine[j] - prevLine[j + channel]
                            - curLine[j] + 9 * curLine[j] - curLine[j + channel]
                            - 2 * nextLine[j] - nextLine[j + channel];
                }
                else
                {
                    if (j + channel >= width * channel) // последний столбец (+)
                    {
                        pixel = - prevLine[j - channel] - 2 * prevLine[j]
                                - curLine[j - channel] + 9 * curLine[j] - curLine[j]
                                - nextLine[j - channel] - 2 * nextLine[j];
                    }
                    else    // все остальные нормальные пиксели, а не вот это вот
                    {
                        pixel = - prevLine[j - channel] - prevLine[j] - prevLine[j + channel]
                                - curLine[j - channel] + 9 * curLine[j] - curLine[j + channel]
                                - nextLine[j - channel] - nextLine[j] - nextLine[j + channel];
                    }
                }
            }
//            std::cout << " " << pixel << std::endl;
            pixel = pixel > 255 ? 255: pixel;
            pixel = pixel < 0 ? 0: pixel;
            resLine[j] = (unsigned char)pixel;
        }
    }
}

int main() {

    std::string names[] = { "ocean"};
    for (int i = 0; i < sizeof(names) / sizeof(names[0]); i++) {

        unsigned char* data = nullptr;
        unsigned int w = 0;
        unsigned int h = 0;
        unsigned int channels = 0;

        __loadPPM((R"(D:\AVP\LABS\pictures\forLab\src\)" + names[i] + ".pgm").c_str(), &data, &w, &h, &channels);
        unsigned char* res = (unsigned char*)malloc(w * h * sizeof(unsigned char) * channels);
        unsigned char* res_dev = (unsigned char*)malloc(w * h * sizeof(unsigned char) * channels);

        memset(res, 0, w * h * sizeof(unsigned char) * channels);
        double host_time = measureTime(Host_Filter, data, res, w, h, channels);
        std::cout << "host " + names[i] + " (" << w << 'x' << h << "): " << host_time << " ms\n";
        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_host.pgm").c_str(), res, w, h, channels);

//        memset(res_dev, 0, w * h * sizeof(unsigned char) * channels);
//        double device_time = grey_filter(res_dev, data, w, h);
//        std::cout << "device " + names[i] + " (" << w << 'x' << h << "): " << device_time << " ms\n";
//        CmpResult(res, res_dev, w * h * channels * sizeof(unsigned char), "host", "device");
//        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_device.pgm").c_str(), res_dev, w, h, channels);

        double device_opt_time = grey_filter_Optimized(res_dev, data, w, h);
        std::cout << "device optimized " + names[i] + " (" << w << 'x' << h << "): " << device_opt_time << " ms\n";
        CmpResult(res, res_dev, w * h * channels * sizeof(unsigned char), "res", "device optimized");
        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_device_opt.pgm").c_str(), res_dev, w, h, channels);

//        for (int i = 0; i < h; i++) {
//            for (int j = 0; j < w; j++) {
//                if (res[i * w + j] != res_dev[i * w + j])
//                {
//                    std::cout << (unsigned int)res[i * w + j] << ' ' << (unsigned int)res_dev[i * w + j] << ' ' << i << ' ' << j << '\n';
//                }
//            }
//        }
//        double dev_load_time = measureTime(
//        std::cout << names[i] + "_device.pgm" + " write time - " << dev_load_time << " ms\n";
//        std::cout << "\n";


        free(data);
        free(res);
        free(res_dev);
    }

    for (int i = 0; i < sizeof(names) / sizeof(names[0]); i++) {

        unsigned char* data = nullptr;
        unsigned int w = 0;
        unsigned int h = 0;
        unsigned int channels = 0;

        __loadPPM((R"(D:\AVP\LABS\pictures\forLab\src\)" + names[i] + ".ppm").c_str(), &data, &w, &h, &channels);

        unsigned char* res = (unsigned char*)malloc(w * h * sizeof(unsigned char) * channels);
        unsigned char* res_dev = (unsigned char*)malloc(w * h * sizeof(unsigned char) * channels);

        memset(res, 0, w * h * sizeof(unsigned char) * channels);
        double host_time = measureTime(Host_Filter, data, res, w, h, channels);
        std::cout << "Host " + names[i] + " (" << w << 'x' << h << "): " << host_time << " ms\n";
        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_host.ppm").c_str(), res, w, h, channels);

//        memset(res_dev, 0, w * h * sizeof(unsigned char) * channels);
//        double device_opt_time = RGB_filter(res_dev, data, w, h);
//        std::cout << "Device  " + names[i] + " (" << w << 'x' << h << "): " << device_opt_time << " ms\n";
//        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_device.ppm").c_str(), res_dev, w, h, channels);
//        CmpResult(res_dev, res, w * h * channels * sizeof(unsigned char), "Host", "Device");

        memset(res_dev, 0, w * h * sizeof(unsigned char) * channels);
        double device_time = RGB_filter_Optimized(res_dev, data, w, h);
        std::cout << "Device optimized " + names[i] + " (" << w << 'x' << h << "): " << device_time << " ms\n";
        __savePPM((R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_device_opt.ppm").c_str(), res_dev, w, h, channels);
        CmpResult(res_dev, res, w * h * channels * sizeof(unsigned char), "Host", "Device opt");

//        double dev_load_time = measureTime(__savePPM, (R"(D:\AVP\LABS\pictures\forLab\result\)" + names[i] + "_device.ppm").c_str(), res_dev, w, h, channels);
//        std::cout << names[i] + "_device.ppm" + " write time - " << dev_load_time << " ms\n";
//        std::cout << "\n";

        free(data);
        free(res);
        free(res_dev);
    }

    // cudaDeviceReset must be called before exiting in order for profiling and
// tracing tools such as Nsight and Visual Profiler to show complete traces.
    cudaError_t cudaStatus = cudaDeviceReset();
    if (cudaStatus != cudaSuccess) {
        std::cerr << "cudaDeviceReset failed!\n";
        return 1;
    }

    return 0;
}