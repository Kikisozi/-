# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v5 Dobby最终版] 开始编译 ---"
	# -L. : 告诉链接器在当前目录查找库文件
	# -ldobby: 告诉链接器链接dobby静态库 (libdobby.a)
	clang -v -I. -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES \
	-L. -ldobby \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [v5 Dobby最终版] 编译完成 ---"
