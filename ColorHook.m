#import <Foundation/Foundation.h>
#import <dlfcn.h> // 用于 dlsym, dlopen
#import <math.h>   // 用于 fabsf
#import <GLES2/gl2.h> // 用于 OpenGL ES 类型

// --- 这是Cydia Substrate的核心Hook函数声明 ---
// 您需要将 substrate.h 文件放到您的项目或include路径中
// 或者为了简单，直接在此处声明函数原型
void MSHookFunction(void *symbol, void *replace, void **result);

// --- 1. 配置颜色常量 ---
const GLfloat TARGET_R = 0.25365f;
const GLfloat TARGET_G = 0.10376f;
const GLfloat TARGET_B = 0.23924f;
const GLfloat TARGET_A = 0.47196f;

const GLfloat REPLACEMENT_R = 0.645f;
const GLfloat REPLACEMENT_G = 0.424f;
const GLfloat REPLACEMENT_B = 1.12f;
const GLfloat REPLACEMENT_A = 0.480f;

const float EPSILON = 0.0001f; // 浮点数比较的容差

// --- 2. 定义一个函数指针，用于保存原始函数的地址 ---
static void (*original_glUniform4fv)(GLint location, GLsizei count, const GLfloat *value);

// --- 3. 编写我们的替换函数，函数签名必须与原函数完全一致 ---
void replacement_glUniform4fv(GLint location, GLsizei count, const GLfloat *value) {
    // 仅处理单颜色设置的调用，提高效率
    if (count == 1 && value != NULL) {
        // 快速检查第一个R值，若不匹配则立即调用原函数，避免不必要的计算
        if (fabsf(value[0] - TARGET_R) < EPSILON) {
            // 当找到完整匹配的目标颜色时
            if (fabsf(value[1] - TARGET_G) < EPSILON &&
                fabsf(value[2] - TARGET_B) < EPSILON &&
                fabsf(value[3] - TARGET_A) < EPSILON) {
                
                // C语言的const指针理论上不应修改，但为了实现与Frida脚本相同的内存直接覆写逻辑，
                // 我们需要进行强制类型转换来移除const属性。这是一个高风险操作，但在此场景下是必要的。
                GLfloat* mutable_value = (GLfloat*)value;
                
                mutable_value[0] = REPLACEMENT_R;
                mutable_value[1] = REPLACEMENT_G;
                mutable_value[2] = REPLACEMENT_B;
                mutable_value[3] = REPLACEMENT_A;
            }
        }
    }
    
    // 无论是否修改，都必须调用原始函数，否则游戏将无法正常渲染
    original_glUniform4fv(location, count, value);
}

// --- 4. 编写构造函数，在dylib被加载时自动执行 ---
// __attribute__((constructor)) 是一个编译器指令，确保此函数在dylib加载时首先被调用
__attribute__((constructor))
static void initialize() {
    // 使用dlopen打开OpenGLES框架的句柄
    // RTLD_LAZY: 懒加载模式
    void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
    if (!handle) return;
    
    // 使用dlsym从句柄中查找原始glUniform4fv函数的地址
    void *original_function_ptr = dlsym(handle, "glUniform4fv");
    if (!original_function_ptr) return;
    
    // 使用MSHookFunction进行Hook
    // 1. 传入原始函数地址
    // 2. 传入我们编写的替换函数地址
    // 3. 传入一个指针的地址，用于保存原始函数的调用入口
    MSHookFunction(original_function_ptr, (void *)replacement_glUniform4fv, (void **)&original_glUniform4fv);
    
    dlclose(handle); // 完成后关闭句柄
}
