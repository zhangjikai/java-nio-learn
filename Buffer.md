# 缓冲区

<!-- toc -->

缓冲区本质上就是一块内存，可以向该内存中写入数据以及从内存中读取数据。这块内存被包装成 NIO Buffer 对象，并提供了相关的 API，以方便的访问这块内存。需要注意的是缓冲区在读模式和写模式下有不同的行为。

## 属性
缓冲区通过四个属性来描述它所包含的数据信息：

* **capacity（容量）**    
    缓冲区能被容纳元素的最大数量。当缓冲区被创建之后，它的容量就已经确定了，在使用过程中不可改变

* **position（位置）**  
    表示下一个要被读或者写的元素的索引。position 的最大有效值为 capacity-1。

* **limit（上界）**
  * 当缓冲区处于写模式时，limit 表示最多能往 Buffer 里写入的数据。该模式下，limit 就等于 Buffer 的 capacity。
  * 当缓冲区处于读模式时，limit 表示最多可以读到的数据。在该模式下，limit 会被设置为写模式下的 positoin 值。

* **mark（标记）**  
    保存一个 position 信息备份。通过调用 mark() 方法，可以将 mark 值设为当前 position 值，即 mark=position。随后再调用 reset 方法时，会将 position 值重置为 mark 值。初始时 mark 是未定义的，只有调用了 mark() 方法之后，mark 值才被定义。

## 初始化
Buffer 的子类有很多，这里我们以 ByteBuffer 为例，来看下缓冲区处于不同模式下的结构变化。下图是缓冲区刚被创建时的状态，此时缓冲区处于写模式。这里 mark 被设为 -1，用来表示 mark 是未定义的 （undefined）。我们看到缓冲区实际上就是一个数组加上我们前面说的几个属性，注意这里创建了一个长度为 10 的缓存区，索引从 0 - 9，10 元素是不存在，这里为了方便描述，绘制了一个虚拟的 10 号元素。

![](/images/buffer_init.png)
> 图片参考 Java NIO

## 写入数据

我们有两种方式向 Buffer 里写数据：
* 从 Channel 里写到 Buffer
    ```java
    int bytesRead = inChannel.read(buf); //read into buffer.
    ```
* 通过 Buffer 的 put 方法
    ```java
    buf.put('A');
    ```

假设我们向缓冲区中写入了 5 个元素，那么此时缓冲区就变为下面的状态：

![](/images/写入元素.png)

在向缓冲区写入的过程中，会首先数据写入到 position 对应的位置，然后对 position 执行加 1 操作，下面是代码实现：
```java
final int nextPutIndex() { // package-private
    if (position >= limit)
        throw new BufferOverflowException();
    return position++;
}
```

## 读取数据

下面我们再来看下缓冲区的读操作。通过 flip 方法，可以将缓冲区切换到读取模式，我们看下 flip 方法的实现：
```java
public final Buffer flip() {
    limit = position;
    position = 0;
    mark = -1;
    return this;
}
```
我们看到 flip 方法中其实做了3件事：
* 将 limit 设为 position：在读模式下，limit 主要用来标记缓冲区中可读元素的上限，也就是在读之前，缓冲区中已经写入的元素数量。根据缓冲区写入的过程，缓冲区中已经写入的元素个数其实就是写模式下的 position 值，所以这里将 limit 设为 position。
* 将 position 设为 0：因为缓冲区是顺序写入，所以我们从 0 开始都即可。
* 重置 mark。

下面是执行 flip 方法之后缓冲区的状态：

![](/images/读取元素.png)

然后我们可以通过下面两种方式从缓冲区中读数据：
* 将 Buffer 数据读入到 Channel 中
  ```java
  int bytesWritten = inChannel.write(buf);
  ```
* 调用 Buffer 的 get 方法，get 方法有多个版本，具体的参见 JDK 文档。
  ```java
  byte aByte = buf.get();
  ```

如果我们希望重新读数据，可以调用 rewind 方法，该方法会将 position 置为 0，而 limit 保持不变，下面是该方法的实现：
```java
public final Buffer rewind() {
    position = 0;
    mark = -1;
    return this;
}
```
在读取完 position 位置的数据之后，也会将 position 的值加 1。另外从上面的图我们也可以看出，不管是读模式和写模式，Buffer 的 capatity 值是一致的。

## 释放缓冲区
当读完缓冲区的数据之后，需要让 buffer 准备好再次被写入，也就是将缓冲区中的数据释放掉。我们可以通过 clear() 或者 compact() 方法来清除数据。我们首先看下 clear 方法，下面是实现代码：
```java
public final Buffer clear() {
    position = 0;
    limit = capacity;
    mark = -1;
    return this;
}
```
我们看到 clear 方法只是重置了 position、limit 和 mark 这 3 个变量，Buffer 中原有的数据并没有被清除。

![](/images/清除元素.png)

在看 compact 方法之前，我们首先看下 hasRemaining 和 remaining 方法：
* hasRemaining - 查询是否还有剩余元素
  * 写模式 - 检查缓冲区中是否还有空闲的空间可以写入，
  * 读模式 - 检查缓冲区中是否还有未读的元素
  ```java
  public final boolean hasRemaining() {
      return position < limit;
  }
  ```
* remaining - 返回剩余元素的个数
  * 写模式 - 返回空闲元素的个数
  * 读模式 - 返回未读元素的个数
  ```java
  public final int remaining() {
      return limit - position;
  }
  ```

compact 方法会保留未读数据。该方法首先将所有未读的元素拷贝到 Buffer 起始处，然后将 position 指向最后一个未读元素的后面，下图是一个示例。下图中我们假设缓冲区已经被读了两个元素，然后对该缓冲区调用 compact 方法。

![](/images/compact.png)

下面我们看下 ByteBuffer 中 compact 方法的实现：
```java
public ByteBuffer compact() {
    // 复制 Buffer 剩余元素到 Buffer 起始处
    System.arraycopy(hb, ix(position()), hb, ix(0), remaining());
    // 设置 position为剩余元素个数值
    position(remaining());
    // 设置 limit 值为 capacity
    limit(capacity());
    // 重置 mark
    discardMark();
    return this;
}

/**
 * @param      src      the source array.
 * @param      srcPos   starting position in the source array.
 * @param      dest     the destination array.
 * @param      destPos  starting position in the destination data.
 * @param      length   the number of array elements to be copied.
 */
public static native void arraycopy(Object src, int srcPos,
    Object dest, int destPos, int length);
```
## 标记
下面我们来看下 mark 属性。mark 属性主要用来设置一个标记，然后我们可以将 position 重置到 mark 标记的位置。通过调用 mark() 方法会将 mark 的值设为当前的 position 值，当调用 reset() 方法时，会将 position 重置为 mark 值，如果 mark 未定义，会抛出 InvalidMarkException 异常。注意我们前面说的 rewind()、clear()、flip() 方法会重置 mark 值，下面是两个方法的实现：
```java
public final Buffer mark() {
    mark = position;
    return this;
}

public final Buffer reset() {
    int m = mark;
    if (m < 0)
        throw new InvalidMarkException();
    position = m;
    return this;
}
```
## 类别
NIO 中提供了不同的 Buffer 用来存储不同的数据类型，主要包含下面几种：
* CharBuffer
* ShortBuffer
* IntBuffer
* LongBuffer
* FloatBuffer
* DoubleBuffer
* ByteBuffer

下面是相关的数据类型以及大小

| 数据类型 | 大小(字节数量) |
|:---|:---|
| char | 2  |
| short | 2 |
| int | 4 |
| long | 8 |
| float | 4 |
| double | 8 |
| byte | 1 |

其中 ByteBuffer 比较特殊，它以字节为单位，可以通过 asXXXBuffer 方法转换成其他类型的 Buffer，例如转换为 CharBuffer：`byteBuffer.asCharBuffer()`。需要注意的一点是转换成 CharBuffer 时会有编码问题，这个在后面讨论。
