# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v6 零依赖最终版] 开始编译 ---"
	# 只编译我们自己的源代码，不再有任何外部链接
	clang -v -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [v6 零依赖最终版] 编译完成 ---"
