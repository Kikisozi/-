#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <OpenGLES/ES2/gl.h>
#import <UIKit/UIKit.h>

// ===================================================================
// --- 自包含的迷你Hook工具 (无需改动) ---
static inline bool InstallHook(void *target, void *replacement, void **original_trampoline) {
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
    *original_trampoline = trampoline;
    return true;
}
// ===================================================================

// --- 全局变量 ---
static UIWindow *floatingWindow;
static UILabel *statusLabel;
static UITextView *logTextView;
static UIButton *hookButton;

static bool isHookInstalled = false;
static bool isMonitoringEnabled = false; // 开关现在用于控制监控
static long long drawCallCount = 0;   // 绘制调用计数器

// --- Hook目标函数原型 ---
static void (*original_glDrawElements)(GLenum mode, GLsizei count, GLenum type, const void *indices);

// ===================================================================
// --- 核心功能与UI控制类 ---
// ===================================================================
@interface GLESMonitorController : NSObject
+ (instancetype)sharedInstance;
- (void)panGesture:(UIPanGestureRecognizer *)p;
- (void)toggleMonitoring:(UIButton *)sender;
@end

// 日志函数
void addLog(NSString *logMessage) {
    if (!logTextView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [logTextView.text stringByAppendingFormat:@"%@\n", logMessage];
        logTextView.text = newText;
        [logTextView scrollRangeToVisible:NSMakeRange(newText.length, 0)];
    });
}

// 【重要改动】替换函数现在监控glDrawElements
void replacement_glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices) {
    if (isMonitoringEnabled) {
        drawCallCount++;
        
        // 为了避免日志刷屏，我们只在UI上更新计数，并每隔一段时间打印一次日志
        if (drawCallCount % 200 == 1) { // 每调用200次
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = [NSString stringWithFormat:@"状态: 捕获到绘制! (x%lld)", drawCallCount];
            });
            // 打印更详细的信息
            addLog([NSString stringWithFormat:@"[Call %lld] mode:0x%X, count:%d", drawCallCount, mode, count]);
        }
    }
    
    // 必须调用原始函数，否则游戏画面将不会被渲染
    original_glDrawElements(mode, count, type, indices);
}

@implementation GLESMonitorController
+ (instancetype)sharedInstance {
    static GLESMonitorController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GLESMonitorController alloc] init];
    });
    return instance;
}

- (void)panGesture:(UIPanGestureRecognizer *)p {
    UIView *window = p.view;
    CGPoint panPoint = [p translationInView:window];
    window.center = CGPointMake(window.center.x + panPoint.x, window.center.y + panPoint.y);
    [p setTranslation:CGPointZero inView:window];
}

// 【重要改动】按钮现在控制监控的开启和关闭
- (void)toggleMonitoring:(UIButton *)sender {
    if (!isHookInstalled) {
        addLog(@"首次点击，开始安装Hook...");
        void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
        if (!handle) { addLog(@"错误: 无法打开OpenGLES框架!"); return; }
        addLog(@"成功打开OpenGLES。");
        
        void *target_func_ptr = dlsym(handle, "glDrawElements");
        if (!target_func_ptr) { addLog(@"错误: 无法找到glDrawElements函数!"); dlclose(handle); return; }
        addLog(@"成功定位glDrawElements。");
        
        bool success = InstallHook(target_func_ptr, (void *)replacement_glDrawElements, (void **)&original_glDrawElements);
        
        if (success) {
            isHookInstalled = true;
            isMonitoringEnabled = true;
            drawCallCount = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"状态: 监控中...";
                [sender setTitle:@"停止监控" forState:UIControlStateNormal];
                sender.backgroundColor = [UIColor systemRedColor];
            });
            addLog(@"注入成功，监控已开启。");
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ statusLabel.text = @"状态: 注入失败!"; });
            addLog(@"注入失败!");
        }
        dlclose(handle);
    } else {
        isMonitoringEnabled = !isMonitoringEnabled;
        if (isMonitoringEnabled) {
            drawCallCount = 0;
            statusLabel.text = @"状态: 监控中...";
            [sender setTitle:@"停止监控" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemRedColor];
            addLog(@"监控已开启。");
        } else {
            statusLabel.text = @"状态: 监控已停止";
            [sender setTitle:@"开始监控" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemBlueColor];
            addLog(@"监控已停止。");
        }
    }
}
@end

void createFloatingWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 250, 200)];
        floatingWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
        floatingWindow.layer.cornerRadius = 10;
        floatingWindow.layer.masksToBounds = true;
        floatingWindow.windowLevel = UIWindowLevelAlert + 1;
        floatingWindow.hidden = NO;
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[GLESMonitorController sharedInstance] action:@selector(panGesture:)];
        [floatingWindow addGestureRecognizer:pan];

        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 20)];
        statusLabel.text = @"状态: 等待操作";
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [floatingWindow addSubview:statusLabel];

        hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hookButton.frame = CGRectMake(10, 40, 230, 30);
        [hookButton setTitle:@"安装并开始监控" forState:UIControlStateNormal];
        [hookButton addTarget:[GLESMonitorController sharedInstance] action:@selector(toggleMonitoring:) forControlEvents:UIControlEventTouchUpInside];
        hookButton.backgroundColor = [UIColor systemGreenColor];
        [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookButton.layer.cornerRadius = 5;
        [floatingWindow addSubview:hookButton];

        logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 80, 230, 110)];
        logTextView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        logTextView.textColor = [UIColor systemTealColor];
        logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        logTextView.editable = NO;
        logTextView.text = @"日志输出:\n";
        [floatingWindow addSubview:logTextView];
    });
}

// ===================================================================
// --- 主构造函数 ---
// ===================================================================
__attribute__((constructor))
static void initialize() {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification 
                                                      object:nil 
                                                       queue:[NSOperationQueue mainQueue] 
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            createFloatingWindow();
        });
        
    }];
}
