import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Suno Webhook Edge Function
// 处理来自 Suno API 的生成结果回传

Deno.serve(async (req) => {
  // 处理预检请求 (CORS)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { 
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      }
    })
  }

    try {
    // 1. 安全校验：检查 URL 中的 token 参数
    const url = new URL(req.url)
    const token = url.searchParams.get('token')
    const expectedToken = Deno.env.get('SUNO_WEBHOOK_TOKEN')

    if (!token || token !== expectedToken) {
      console.error(`[Security] 未经授权的访问尝试。Token: ${token}`)
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { 
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    const rawText = await req.text()
    console.log('--- 收到 Suno 回调原始数据 ---')
    console.log(rawText)
    
    const payload = JSON.parse(rawText)
    const { code, msg, data } = payload
    
    // 初始化 Supabase 客户端
    // 优先使用标准环境变量，如果没有则使用自定义变量
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? Deno.env.get('MY_PROJECT_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('MY_SERVICE_ROLE_KEY') ?? ''
    
    if (!supabaseUrl || !supabaseServiceKey) {
      console.error('缺少 Supabase 配置环境变量')
      return new Response(JSON.stringify({ error: 'Server configuration error' }), { status: 500 })
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    if (code === 200 && data) {
      // 核心修正：兼容 taskId 和 task_id
      const taskId = data.taskId || data.task_id
      const callbackType = data.callbackType

      if (!taskId) {
        console.error('回调数据中缺少 taskId')
        return new Response(JSON.stringify({ error: 'Missing taskId' }), { status: 400 })
      }

      if (callbackType === 'complete' && data.data && data.data.length > 0) {
        const musicData = data.data[0] // 获取生成的第一个音乐数据

        console.log(`正在更新任务 ${taskId} 的生成结果...`)
        console.log(`音频 URL: ${musicData.audio_url}`)

        // 更新数据库中的记录
        const { data: updateResult, error: updateError } = await supabase
          .from('music_generations')
          .update({
            status: 'completed',
            audio_url: musicData.audio_url,
            image_url: musicData.image_url,
            suno_audio_id: musicData.id, // Suno 音频 track ID，用于歌词 API
            title: musicData.title || 'Untitled',
            payload: payload // 保存完整的原始回调数据以便查阅
          })
          .eq('task_id', taskId)
          .select() // 返回更新后的数据以确认是否成功

        if (updateError) {
          console.error(`数据库更新失败 (Task: ${taskId}):`, updateError)
          return new Response(JSON.stringify({ error: updateError.message }), { status: 500 })
        }

        if (!updateResult || updateResult.length === 0) {
          console.warn(`未找到对应的任务记录 (Task: ${taskId})，请检查数据库中是否存在该 task_id`)
        } else {
          console.log(`任务 ${taskId} 更新成功！受影响行数: ${updateResult.length}`)
        }

      } else if (callbackType === 'error') {
        console.warn(`任务 ${taskId} 生成失败:`, msg)
        
        await supabase
          .from('music_generations')
          .update({
            status: 'failed',
            payload: payload
          })
          .eq('task_id', taskId)
      }
    } else {
      console.warn('收到无效或非 200 状态码回调:', code, msg)
    }

    return new Response(JSON.stringify({ status: 'success' }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200
    })

  } catch (error) {
    console.error('处理回调异常:', error)
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})