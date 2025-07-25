#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <OpenGLES/ES2/gl.h>
#import <UIKit/UIKit.h>

// ===================================================================
// --- 自包含的迷你Hook工具 ---
// 经过审查，确保在标准编译环境中可用，并移除了所有不可用的函数调用
// ===================================================================
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
    if (kr != KERN_SUCCESS) {
        munmap(trampoline, patch_size + 4);
        return false;
    }
    
    intptr_t offset_to_replacement = (intptr_t)replacement - (intptr_t)target;
    uint32_t branch_instruction = 0x14000000 | (0x03FFFFFF & (offset_to_replacement >> 2));
    memcpy(target, &branch_instruction, sizeof(branch_instruction));
    
    vm_protect(mach_task_self(), (vm_address_t)target, patch_size, false, VM_PROT_READ | VM_PROT_EXECUTE);
    
    *original_trampoline = trampoline;
    return true;
}

// ===================================================================
// --- 全局变量和颜色常量 ---
// ===================================================================
static UIWindow *floatingWindow;
static UILabel *statusLabel;
static UITextView *logTextView;
static UIButton *hookButton;

static bool isHookInstalled = false; // 标记Hook是否已安装
static bool isHookEnabled = false;   // Hook功能的开关
static int replacementCount = 0;
static NSMutableSet *loggedColors;   // 用于存储已经打印过的颜色，避免日志刷屏

// 这里的颜色值是占位符，您需要用下面日志捕获到的真实值来替换它们
const GLfloat TARGET_R = 0.0f;
const GLfloat TARGET_G = 0.0f;
const GLfloat TARGET_B = 0.0f;
const GLfloat TARGET_A = 0.0f;

const GLfloat REPLACEMENT_R = 0.645f; // 新颜色保持不变
const GLfloat REPLACEMENT_G = 0.424f;
const GLfloat REPLACEMENT_B = 1.12f;
const GLfloat REPLACEMENT_A = 0.480f;

const float EPSILON = 0.001f; // 稍微放宽容差

static void (*original_glUniform4fv)(GLint location, GLsizei count, const GLfloat *value);

// ===================================================================
// --- 核心功能与UI控制类 ---
// ===================================================================
@interface ColorHookController : NSObject
+ (instancetype)sharedInstance;
- (void)panGesture:(UIPanGestureRecognizer *)p;
- (void)toggleHook:(UIButton *)sender;
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

// 替换函数 (包含颜色捕获日志)
void replacement_glUniform4fv(GLint location, GLsizei count, const GLfloat *value) {
    if (isHookEnabled && count == 1 && value != NULL) {
        const GLfloat r = value[0];
        const GLfloat g = value[1];
        const GLfloat b = value[2];
        const GLfloat a = value[3];

        // 捕获并打印所有独特的颜色值
        NSString *colorKey = [NSString stringWithFormat:@"%.3f,%.3f,%.3f,%.3f", r, g, b, a];
        if (![loggedColors containsObject:colorKey]) {
            [loggedColors addObject:colorKey];
            addLog([NSString stringWithFormat:@"捕获新颜色 R:%.3f G:%.3f B:%.3f A:%.3f", r, g, b, a]);
        }
        
        // 检查颜色是否匹配
        if (fabsf(r - TARGET_R) < EPSILON && fabsf(g - TARGET_G) < EPSILON &&
            fabsf(b - TARGET_B) < EPSILON && fabsf(a - TARGET_A) < EPSILON) {
            
            GLfloat* mutable_value = (GLfloat*)value;
            mutable_value[0] = REPLACEMENT_R;
            mutable_value[1] = REPLACEMENT_G;
            mutable_value[2] = REPLACEMENT_B;
            mutable_value[3] = REPLACEMENT_A;
            
            replacementCount++;
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = [NSString stringWithFormat:@"状态: 颜色已替换! (x%d)", replacementCount];
            });
            if (replacementCount == 1) {
                addLog(@"匹配成功并已替换颜色！");
            }
        }
    }
    // 必须调用原始函数
    original_glUniform4fv(location, count, value);
}

@implementation ColorHookController
+ (instancetype)sharedInstance {
    static ColorHookController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ColorHookController alloc] init];
    });
    return instance;
}

- (void)panGesture:(UIPanGestureRecognizer *)p {
    UIView *window = p.view;
    CGPoint panPoint = [p translationInView:window];
    window.center = CGPointMake(window.center.x + panPoint.x, window.center.y + panPoint.y);
    [p setTranslation:CGPointZero inView:window];
}

- (void)toggleHook:(UIButton *)sender {
    if (!isHookInstalled) {
        addLog(@"首次点击，开始安装Hook...");
        void *handle = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY);
        if (!handle) { addLog(@"错误: 无法打开OpenGLES框架!"); return; }
        addLog(@"成功打开OpenGLES。");
        
        void *original_function_ptr = dlsym(handle, "glUniform4fv");
        if (!original_function_ptr) { addLog(@"错误: 无法找到glUniform4fv函数!"); dlclose(handle); return; }
        addLog(@"成功定位glUniform4fv。");
        
        bool success = InstallHook(original_function_ptr, (void *)replacement_glUniform4fv, (void **)&original_glUniform4fv);
        
        if (success) {
            isHookInstalled = true;
            isHookEnabled = true;
            loggedColors = [NSMutableSet new];
            replacementCount = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"状态: 颜色捕获中...";
                [sender setTitle:@"关闭Hook" forState:UIControlStateNormal];
                sender.backgroundColor = [UIColor systemRedColor];
            });
            addLog(@"注入成功，颜色捕获已开启。");
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                statusLabel.text = @"状态: 注入失败!";
            });
            addLog(@"注入失败!");
        }
        dlclose(handle);
    } else {
        isHookEnabled = !isHookEnabled;
        if (isHookEnabled) {
            [loggedColors removeAllObjects];
            replacementCount = 0;
            statusLabel.text = @"状态: 颜色捕获中...";
            [sender setTitle:@"关闭Hook" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemRedColor];
            addLog(@"Hook功能已开启。");
        } else {
            statusLabel.text = @"状态: Hook已关闭";
            [sender setTitle:@"执行Hook" forState:UIControlStateNormal];
            sender.backgroundColor = [UIColor systemBlueColor];
            addLog(@"Hook功能已关闭。");
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
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ColorHookController sharedInstance] action:@selector(panGesture:)];
        [floatingWindow addGestureRecognizer:pan];

        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 20)];
        statusLabel.text = @"状态: 等待操作";
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [floatingWindow addSubview:statusLabel];

        hookButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hookButton.frame = CGRectMake(10, 40, 230, 30);
        [hookButton setTitle:@"安装并执行Hook" forState:UIControlStateNormal];
        [hookButton addTarget:[ColorHookController sharedInstance] action:@selector(toggleHook:) forControlEvents:UIControlEventTouchUpInside];
        hookButton.backgroundColor = [UIColor systemGreenColor];
        [hookButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hookButton.layer.cornerRadius = 5;
        [floatingWindow addSubview:hookButton];

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
