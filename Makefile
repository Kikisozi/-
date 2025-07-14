# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v3 最终版] 开始编译 ---"
	# -v: 启用详细模式，打印所有编译步骤
	# 调整了参数顺序，将输入文件放在输出文件之前
	clang -v -I. -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [v3 最终版] 编译完成 ---"
