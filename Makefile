# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- 开始编译 ---"
	# 使用clang编译器进行编译
	# 注意：多行命令的每一行末尾都必须有反斜杠 \
	clang -I. -dynamiclib -arch arm64 \
	-isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
	-framework Foundation \
	-framework OpenGLES \
	-o $(DYLIB_NAME) ColorHook.m
	@echo "--- 编译完成: $(DYLIB_NAME) ---"

# 定义清理任务（可选）
clean:
	rm -f $(DYLIB_NAME)
