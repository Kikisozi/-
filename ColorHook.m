#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <OpenGLES/ES2/gl.h>

// ===================================================================
// --- 自包含的迷你Hook工具 ---
// 一个精简的、用于AArch64架构的Inline Hook实现，不再依赖外部库。
static inline bool InstallHook(void *target, void *replacement, void **original_trampoline) {
    if (!target || !replacement || !original_trampoline) return false;

    // AArch64指令为4字节宽。我们为蹦床（trampoline）保存4条指令（16字节）以确保安全。
    size_t patch_size = 16; 

    // 创建蹦床：用于存放原始指令 + 一个跳回原函数的跳转指令
    void *trampoline = mmap(NULL, patch_size + 4, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (trampoline == MAP_FAILED) return false;

    // 1. 将原始函数开头的指令复制到蹦床
    memcpy(trampoline, target, patch_size);

    // 2. 在蹦床末尾添加一个跳回原函数（在被覆盖部分之后）的跳转指令
    uintptr_t jump_back_target = (uintptr_t)target + patch_size;
    uint32_t *jump_back_instruction_ptr = (uint32_t *)((uintptr_t)trampoline + patch_size);
    intptr_t offset_back = jump_back_target - (intptr_t)jump_back_instruction_ptr;
    *jump_back_instruction_ptr = 0x14000000 | (0x03FFFFFF & (offset_back >> 2)); // B instruction

    // 3. 使蹦床的内存页变为可执行
    mprotect(trampoline, patch_size + 4, PROT_READ | PROT_EXEC);

    // 4. 修改目标函数的内存页为可写
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)target, patch_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        munmap(trampoline, patch_size + 4);
        return false;
    }
    
    // 5. 将一个跳转到我们替换函数的指令写入目标函数的开头
    intptr_t offset_to_replacement = (intptr_t)replacement - (intptr_t)target;
    uint32_t branch_instruction = 0x14000000 | (0x03FFFFFF & (offset_to_replacement >> 2)); // B instruction
    memcpy(target, &branch_instruction, sizeof(branch_instruction));
    
    // 6. 恢复目标函数的原始内存权限
    vm_protect(mach_task_self(), (vm_address_t)target, patch_size, false, VM_PROT_READ | VM_PROT_EXECUTE);

    // 7. 清理指令缓存，确保CPU执行的是我们的新指令
    __builtin_clear_cache((char *)target, (char *)target + patch_size);

    *original_trampoline = trampoline;
    return true;
}
// ===================================================================

// --- 颜色常量 (保持不变) ---
const GLfloat TARGET_R = 0.25365f;
const GLfloat TARGET_G = 0.10376f;
const GLfloat TARGET_B = 0.23924f;
const GLfloat TARGET_A = 0.47196f;
const GLfloat REPLACEMENT_R = 0.645f;
const GLfloat REPLACEMENT_G = 0.424f;
const GLfloat REPLACEMENT_B = 1.12f;
const GLfloat REPLACEMENT_A = 0.480f;
const float EPSILON = 0.0001f;

// --- 定义函数指针保存原始函数地址 ---
static void (*original_glUniform4fv)(GLint location, GLsizei count, const GLfloat *value);

// --- 替换函数 (保持不变) ---
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

// --- 构造函数 (使用我们自己的Hook工具) ---
__attribute__((constructor))
static void initialize() {
    void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
    if (!handle) return;
    
    void *original_function_ptr = dlsym(handle, "glUniform4fv");
    if (!original_function_ptr) return;
    
    // 【重要改动】使用我们自己实现的InstallHook进行Hook
    InstallHook(original_function_ptr, (void *)replacement_glUniform4fv, (void **)&original_glUniform4fv);
    
    dlclose(handle);
}

