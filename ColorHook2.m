#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

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
static long long dataPacketCount = 0;
static NSMutableSet *loggedDataPackets; // 用于存储已打印的数据包，避免刷屏

// --- Hook目标函数原型 ---
static void (*original_setFragmentBytes)(id self, SEL _cmd, const void* bytes, NSUInteger length, NSUInteger index);

// ===================================================================
// --- 核心功能与UI控制类 ---
// ===================================================================
@interface MetalSnifferController : NSObject
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

// 替换函数，监控Metal数据传输
void replacement_setFragmentBytes(id self, SEL _cmd, const void* bytes, NSUInteger length, NSUInteger index) {
    if (isMonitoringEnabled && bytes != NULL) {
        // 我们只关心由4个浮点数构成的数据包 (4 * 4 bytes = 16)
        if (length == 16) {
            dataPacketCount++;
            
            const float* values = (const float*)bytes;
            float v1 = values[0];
            float v2 = values[1];
            float v3 = values[2];
            float v4 = values[3];
            
            // 为了避免日志刷屏，我们只打印不重复的数据包
            NSString *packetKey = [NSString stringWithFormat:@"idx:%lu,%.2f,%.2f,%.2f,%.2f", (unsigned long)index, v1, v2, v3, v4];
            if (![loggedDataPackets containsObject:packetKey]) {
                [loggedDataPackets addObject:packetKey];
                addLog([NSString stringWithFormat:@"[包#%lld][i:%lu] 4浮点值: %.2f, %.2f, %.2f, %.2f", dataPacketCount, (unsigned long)index, v1, v2, v3, v4]);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = [NSString stringWithFormat:@"状态: 捕获到数据包! (x%lld)", dataPacketCount];
            });
        }
    }
    // 必须调用原始方法，否则游戏会崩溃
    original_setFragmentBytes(self, _cmd, bytes, length, index);
}

@implementation MetalSnifferController
+ (instancetype)sharedInstance {
    static MetalSnifferController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MetalSnifferController alloc] init];
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
        addLog(@"首次点击，安装数据嗅探Hook...");
        
        // 尝试多个可能的渲染器类名，增加成功率
        Class targetClass = NSClassFromString(@"MTLDebugRenderCommandEncoder");
        if (!targetClass) { targetClass = NSClassFromString(@"_MTLDebugRenderCommandEncoder"); }
        if (!targetClass) { targetClass = NSClassFromString(@"MTLIOAccelRenderCommandEncoder"); } // 这是一个常见的正式版类名
        
        if (!targetClass) {
            addLog(@"错误: 找不到任何MTLRenderCommandEncoder的实现类!");
            return;
        }

        addLog([NSString stringWithFormat:@"找到目标类: %@", NSStringFromClass(targetClass)]);

        SEL targetSelector = @selector(setFragmentBytes:length:atIndex:);
        Method targetMethod = class_getInstanceMethod(targetClass, targetSelector);
        if (!targetMethod) {
            addLog(@"错误: 在此类中找不到setFragmentBytes...方法!");
            return;
        }
        addLog(@"成功定位数据传输方法。");
            
        void *target_method_ptr = (void *)method_getImplementation(targetMethod);
        bool success = InstallHook(target_method_ptr, (void *)replacement_setFragmentBytes, (void **)&original_setFragmentBytes);

        if (success) {
            isHookInstalled = true;
            isMonitoringEnabled = true;
            loggedDataPackets = [NSMutableSet new];
            dataPacketCount = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"状态: 数据捕获中...";
                [sender setTitle:@"停止捕获" forState:UIControlStateNormal];
                sender.backgroundColor = [UIColor systemRedColor];
            });
            addLog(@"注入成功，数据捕获已开启。");
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ statusLabel.text = @"状态: 注入失败!"; });
            addLog(@"注入失败!");
        }
    } else {
        isMonitoringEnabled = !isMonitoringEnabled;
        if (isMonitoringEnabled) {
            [loggedDataPackets removeAllObjects];
            dataPacketCount = 0;
            statusLabel.text = @"状态: 数据捕获中...";
            [sender setTitle:@"停止捕获" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemRedColor];
            addLog(@"数据捕获已开启。");
        } else {
            statusLabel.text = @"状态: 捕获已停止";
            [sender setTitle:@"开始捕获" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemGreenColor];
            addLog(@"数据捕获已停止。");
        }
    }
}
@end

void createFloatingWindow() {
    dispatch_async(dispatch_get_main_queue(), ^{
        floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 280, 220)];
        floatingWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
        floatingWindow.layer.cornerRadius = 10;
        floatingWindow.layer.masksToBounds = true;
        floatingWindow.windowLevel = UIWindowLevelAlert + 1;
        floatingWindow.hidden = NO;
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[MetalSnifferController sharedInstance] action:@selector(panGesture:)];
        [floatingWindow addGestureRecognizer:pan];

        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 260, 20)];
        statusLabel.text = @"状态: 等待操作";
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [floatingWindow addSubview:statusLabel];

        hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hookButton.frame = CGRectMake(10, 40, 260, 30);
        [hookButton setTitle:@"安装并捕获数据" forState:UIControlStateNormal];
        [hookButton addTarget:[MetalSnifferController sharedInstance] action:@selector(toggleMonitoring:) forControlEvents:UIControlEventTouchUpInside];
        hookButton.backgroundColor = [UIColor systemIndigoColor];
        [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookButton.layer.cornerRadius = 5;
        [floatingWindow addSubview:hookButton];

        logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 80, 260, 130)];
        logTextView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        logTextView.textColor = [UIColor systemOrangeColor];
        logTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        logTextView.editable = NO;
        logTextView.text = @"Metal数据日志:\n";
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
