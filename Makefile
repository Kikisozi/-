# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [v4 最终链接版] 开始编译 ---"
	# -L. : 告诉链接器在当前目录查找库文件
	# -lsubstrate: 告诉链接器链接 substrate 库 (它会自动寻找 libsubstrate.dylib)
	clang -v -I. -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES \
	-L. -lsubstrate \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [v4 最终链接版] 编译完成 ---"
