#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <objc/runtime.h> // 引入Objective-C运行时头文件
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>   // 引入Metal框架头文件

// ===================================================================
// --- 自包含的迷你Hook工具 ---
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
static bool isMonitoringEnabled = false;
static long long metalDrawCallCount = 0;

// --- Hook目标函数原型 ---
static void (*original_drawIndexedPrimitives)(id self, SEL _cmd, MTLPrimitiveType primitiveType, NSUInteger indexCount, MTLIndexType indexType, id<MTLBuffer> indexBuffer, NSUInteger indexBufferOffset);

// ===================================================================
// --- 核心功能与UI控制类 ---
// ===================================================================
@interface MetalMonitorController : NSObject
+ (instancetype)sharedInstance;
- (void)panGesture:(UIPanGestureRecognizer *)p;
- (void)toggleMonitoring:(UIButton *)sender;
@end

void addLog(NSString *logMessage) {
    if (!logTextView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [logTextView.text stringByAppendingFormat:@"%@\n", logMessage];
        logTextView.text = newText;
        [logTextView scrollRangeToVisible:NSMakeRange(newText.length, 0)];
    });
}

// 替换函数，监控Metal绘制调用
void replacement_drawIndexedPrimitives(id self, SEL _cmd, MTLPrimitiveType primitiveType, NSUInteger indexCount, MTLIndexType indexType, id<MTLBuffer> indexBuffer, NSUInteger indexBufferOffset) {
    if (isMonitoringEnabled) {
        metalDrawCallCount++;
        if (metalDrawCallCount % 500 == 1) { // 节流，避免日志刷屏
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = [NSString stringWithFormat:@"状态: 捕获到Metal绘制! (x%lld)", metalDrawCallCount];
            });
            addLog([NSString stringWithFormat:@"[Metal Call %lld] count:%lu", metalDrawCallCount, (unsigned long)indexCount]);
        }
    }
    original_drawIndexedPrimitives(self, _cmd, primitiveType, indexCount, indexType, indexBuffer, indexBufferOffset);
}

@implementation MetalMonitorController
+ (instancetype)sharedInstance {
    static MetalMonitorController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MetalMonitorController alloc] init];
    });
    return instance;
}

- (void)panGesture:(UIPanGestureRecognizer *)p {
    UIView *window = p.view;
    CGPoint panPoint = [p translationInView:window];
    window.center = CGPointMake(window.center.x + panPoint.x, window.center.y + panPoint.y);
    [p setTranslation:CGPointZero inView:window];
}

- (void)toggleMonitoring:(UIButton *)sender {
    if (!isHookInstalled) {
        addLog(@"首次点击，开始安装Metal Hook...");
        Class targetClass = NSClassFromString(@"MTLDebugRenderCommandEncoder");
        if (!targetClass) {
            targetClass = NSClassFromString(@"_MTLDebugRenderCommandEncoder");
            if (!targetClass) { addLog(@"错误: 找不到MTLRenderCommandEncoder类!"); return; }
        }
        addLog(@"成功找到Metal渲染类。");

        SEL targetSelector = @selector(drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:);
        Method targetMethod = class_getInstanceMethod(targetClass, targetSelector);
        if (!targetMethod) { addLog(@"错误: 找不到drawIndexedPrimitives方法!"); return; }
        addLog(@"成功定位Metal绘制方法。");
            
        void *target_method_ptr = (void *)method_getImplementation(targetMethod);

        bool success = InstallHook(target_method_ptr, (void *)replacement_drawIndexedPrimitives, (void **)&original_drawIndexedPrimitives);

        if (success) {
            isHookInstalled = true;
            isMonitoringEnabled = true;
            metalDrawCallCount = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"状态: Metal监控中...";
                [sender setTitle:@"停止监控" forState:UIControlStateNormal];
                sender.backgroundColor = [UIColor systemRedColor];
            });
            addLog(@"注入Metal方法成功，监控已开启。");
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ statusLabel.text = @"状态: Metal注入失败!"; });
            addLog(@"注入Metal方法失败!");
        }
    } else {
        isMonitoringEnabled = !isMonitoringEnabled;
        if (isMonitoringEnabled) {
            metalDrawCallCount = 0;
            statusLabel.text = @"状态: Metal监控中...";
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
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[MetalMonitorController sharedInstance] action:@selector(panGesture:)];
        [floatingWindow addGestureRecognizer:pan];

        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 20)];
        statusLabel.text = @"状态: 等待操作";
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [floatingWindow addSubview:statusLabel];

        hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hookButton.frame = CGRectMake(10, 40, 230, 30);
        [hookButton setTitle:@"安装并监控Metal" forState:UIControlStateNormal];
        [hookButton addTarget:[MetalMonitorController sharedInstance] action:@selector(toggleMonitoring:) forControlEvents:UIControlEventTouchUpInside];
        hookButton.backgroundColor = [UIColor systemIndigoColor];
        [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookButton.layer.cornerRadius = 5;
        [floatingWindow addSubview:hookButton];

        logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 80, 230, 110)];
        logTextView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        logTextView.textColor = [UIColor systemOrangeColor];
        logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        logTextView.editable = NO;
        logTextView.text = @"Metal日志输出:\n";
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
