#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <OpenGLES/ES2/gl.h>

// 引入 Dobby 头文件 (将由工作流自动下载)
#import "dobby.h"

// --- 1. 配置颜色常量 (保持不变) ---
const GLfloat TARGET_R = 0.25365f;
const GLfloat TARGET_G = 0.10376f;
const GLfloat TARGET_B = 0.23924f;
const GLfloat TARGET_A = 0.47196f;

const GLfloat REPLACEMENT_R = 0.645f;
const GLfloat REPLACEMENT_G = 0.424f;
const GLfloat REPLACEMENT_B = 1.12f;
const GLfloat REPLACEMENT_A = 0.480f;

const float EPSILON = 0.0001f;

// --- 2. 定义函数指针保存原始函数地址 ---
static void (*original_glUniform4fv)(GLint location, GLsizei count, const GLfloat *value);

// --- 3. 编写替换函数 (保持不变) ---
void replacement_glUniform4fv(GLint location, GLsizei count, const GLfloat *value) {
    if (count == 1 && value != NULL) {
        if (fabsf(value[0] - TARGET_R) < EPSILON) {
            if (fabsf(value[1] - TARGET_G) < EPSILON &&
                fabsf(value[2] - TARGET_B) < EPSILON &&
                fabsf(value[3] - TARGET_A) < EPSILON) {
                
                GLfloat* mutable_value = (GLfloat*)value;
                mutable_value[0] = REPLACEMENT_R;
                mutable_value[1] = REPLACEMENT_G;
                mutable_value[2] = REPLACEMENT_B;
                mutable_value[3] = REPLACEMENT_A;
            }
        }
    }
    original_glUniform4fv(location, count, value);
}

// --- 4. 编写构造函数，在dylib加载时自动执行 ---
__attribute__((constructor))
static void initialize() {
    void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
    if (!handle) return;
    
    void *original_function_ptr = dlsym(handle, "glUniform4fv");
    if (!original_function_ptr) return;
    
    // 【重要改动】使用 DobbyHook 进行 Hook
    DobbyHook(original_function_ptr, (void *)replacement_glUniform4fv, (void **)&original_glUniform4fv);
    
    dlclose(handle);
}
