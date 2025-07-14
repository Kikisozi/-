# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- 开始编译 ---"
	# 使用clang编译器进行编译
	# -dynamiclib: 指定生成动态库
	# -arch arm64: 指定目标架构为64位ARM（所有现代iOS设备）
	# -isysroot $(xcrun --sdk iphoneos --show-sdk-path): 自动查找并使用最新的iOS SDK
	# -framework ...: 链接必要的系统框架
	# -o $(DYLIB_NAME): 指定输出文件名
	# ColorHook.m: 指定输入的源文件
	clang -dynamiclib -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
	-framework Foundation -framework OpenGLES \
	-o $(DYLIB_NAME) ColorHook.m
	@echo "--- 编译完成: $(DYLIB_NAME) ---"

# 定义清理任务（可选）
clean:
	rm -f $(DYLIB_NAME)
