#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <OpenGLES/ES2/gl.h>
#import <UIKit/UIKit.h> // 引入UIKit框架，用于创建UI

// ===================================================================
// --- 全局变量和UI组件声明 ---
// ===================================================================
static UIWindow *floatingWindow;         // 悬浮窗
static UILabel *statusLabel;             // 状态标签
static UITextView *logTextView;          // 日志视图
static UIButton *hookButton;             // 控制按钮
static bool isHookEnabled = false;       // Hook功能的开关，默认为关闭
static int replacementCount = 0;         // 替换计数器

// ===================================================================
// --- 自包含的迷你Hook工具 (保持不变) ---
// ===================================================================
static inline bool InstallHook(void *target, void *replacement, void **original_trampoline) {
    // ... (此部分代码与上一版完全相同，此处省略以保持简洁)
    if (!target || !replacement || !original_trampoline) return false;
    size_t patch_size = 16; 
    void *trampoline = mmap(NULL, patch_size + 4, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (trampoline == MAP_FAILED) return false;
    memcpy(trampoline, target, patch_size);
    uintptr_t jump_back_target = (uintptr_t)target + patch_size;
    uint32_t *jump_back_instruction_ptr = (uint32_t *)((uintptr_t)trampoline + patch_size);
    intptr_t offset_back = jump_back_target - (intptr_t)jump_back_instruction_ptr;
    *jump_back_instruction_ptr = 0x14000000 | (0x03FFFFFF & (offset_back >> 2));
    mprotect(trampoline, patch_size + 4, PROT_READ | PROT_EXEC);
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)target, patch_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) { munmap(trampoline, patch_size + 4); return false; }
    intptr_t offset_to_replacement = (intptr_t)replacement - (intptr_t)target;
    uint32_t branch_instruction = 0x14000000 | (0x03FFFFFF & (offset_to_replacement >> 2));
    memcpy(target, &branch_instruction, sizeof(branch_instruction));
    vm_protect(mach_task_self(), (vm_address_t)target, patch_size, false, VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate(target, patch_size);
    *original_trampoline = trampoline;
    return true;
}

// ===================================================================
// --- 颜色常量和Hook逻辑 (有改动) ---
// ===================================================================
const GLfloat TARGET_R = 0.25365f;
const GLfloat TARGET_G = 0.10376f;
const GLfloat TARGET_B = 0.23924f;
const GLfloat TARGET_A = 0.47196f;
const GLfloat REPLACEMENT_R = 0.645f;
const GLfloat REPLACEMENT_G = 0.424f;
const GLfloat REPLACEMENT_B = 1.12f;
const GLfloat REPLACEMENT_A = 0.480f;
const float EPSILON = 0.005f;

static void (*original_glUniform4fv)(GLint location, GLsizei count, const GLfloat *value);

// 在主线程安全地添加日志
void addLog(NSString *logMessage) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [logTextView.text stringByAppendingFormat:@"%@\n", logMessage];
        logTextView.text = newText;
        // 自动滚动到底部
        [logTextView scrollRangeToVisible:NSMakeRange(newText.length, 0)];
    });
}

// 替换函数
void replacement_glUniform4fv(GLint location, GLsizei count, const GLfloat *value) {
    // 只有当开关打开时，才执行替换逻辑
    if (isHookEnabled && count == 1 && value != NULL) {
        if (fabsf(value[0] - TARGET_R) < EPSILON && fabsf(value[1] - TARGET_G) < EPSILON &&
            fabsf(value[2] - TARGET_B) < EPSILON && fabsf(value[3] - TARGET_A) < EPSILON) {
            
            GLfloat* mutable_value = (GLfloat*)value;
            mutable_value[0] = REPLACEMENT_R;
            mutable_value[1] = REPLACEMENT_G;
            mutable_value[2] = REPLACEMENT_B;
            mutable_value[3] = REPLACEMENT_A;

            replacementCount++; // 增加计数器
            // 在主线程更新UI，防止崩溃
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = [NSString stringWithFormat:@"状态: 颜色已替换! (x%d)", replacementCount];
            });
            // 每替换10次打印一次日志，避免刷屏
            if (replacementCount % 10 == 1) {
                addLog([NSString stringWithFormat:@"第 %d 次找到并替换颜色。", replacementCount]);
            }
        }
    }
    // 必须调用原始函数
    original_glUniform4fv(location, count, value);
}

// ===================================================================
// --- UI创建和控制逻辑 ---
// ===================================================================
// Hook按钮的点击事件
void toggleHook(UIButton *sender) {
    isHookEnabled = !isHookEnabled; // 切换开关状态
    if (isHookEnabled) {
        replacementCount = 0; // 重置计数器
        statusLabel.text = @"状态: Hook已开启，等待替换...";
        [sender setTitle:@"关闭Hook" forState:UIControlStateNormal];
        addLog(@"Hook功能已开启。");
    } else {
        statusLabel.text = @"状态: Hook已关闭";
        [sender setTitle:@"执行Hook" forState:UIControlStateNormal];
        addLog(@"Hook功能已关闭。");
    }
}

// 悬浮窗的拖动事件
void panGesture(UIPanGestureRecognizer *p) {
    UIWindow *window = p.view;
    CGPoint panPoint = [p translationInView:window];
    window.center = CGPointMake(window.center.x + panPoint.x, window.center.y + panPoint.y);
    [p setTranslation:CGPointZero inView:window];
}

// 创建悬浮窗和所有UI组件
void createFloatingWindow() {
    // 主线程创建UI
    dispatch_async(dispatch_get_main_queue(), ^{
        // 创建悬浮窗
        floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 250, 200)];
        floatingWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
        floatingWindow.layer.cornerRadius = 10;
        floatingWindow.layer.masksToBounds = true;
        floatingWindow.windowLevel = UIWindowLevelAlert + 1; // 确保在最顶层
        floatingWindow.hidden = NO;
        
        // 添加拖动手势
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:NSClassFromString(@"ColorHook") action:@selector(panGesture:)];
        [floatingWindow addGestureRecognizer:pan];

        // 创建状态标签
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 20)];
        statusLabel.text = @"状态: 未注入";
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [floatingWindow addSubview:statusLabel];

        // 创建Hook按钮
        hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hookButton.frame = CGRectMake(10, 40, 230, 30);
        [hookButton setTitle:@"执行Hook" forState:UIControlStateNormal];
        [hookButton addTarget:NSClassFromString(@"ColorHook") action:@selector(toggleHook:) forControlEvents:UIControlEventTouchUpInside];
        hookButton.backgroundColor = [UIColor systemBlueColor];
        [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookButton.layer.cornerRadius = 5;
        [floatingWindow addSubview:hookButton];

        // 创建日志视图
        logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 80, 230, 110)];
        logTextView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        logTextView.textColor = [UIColor greenColor];
        logTextView.font = [UIFont systemFontOfSize:12];
        logTextView.editable = NO;
        logTextView.text = @"日志输出:\n";
        [floatingWindow addSubview:logTextView];
    });
}

// ===================================================================
// --- 主构造函数 (dylib加载入口) ---
// ===================================================================
__attribute__((constructor))
static void initialize() {
    // 1. 先创建UI界面
    createFloatingWindow();

    // 2. 查找目标函数
    void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
    if (!handle) {
        addLog(@"错误: 无法打开OpenGLES框架!");
        return;
    }
    
    void *original_function_ptr = dlsym(handle, "glUniform4fv");
    if (!original_function_ptr) {
        addLog(@"错误: 无法找到glUniform4fv函数!");
        dlclose(handle);
        return;
    }
    
    // 3. 执行Hook
    bool success = InstallHook(original_function_ptr, (void *)replacement_glUniform4fv, (void **)&original_glUniform4fv);
    
    // 4. 根据Hook结果更新UI
    if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            statusLabel.text = @"状态: 注入成功!";
        });
        addLog(@"注入glUniform4fv成功。");
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            statusLabel.text = @"状态: 注入失败!";
        });
        addLog(@"注入glUniform4fv失败!");
    }
    
    dlclose(handle);
}

