import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FCM_ENDPOINT = 'https://fcm.googleapis.com/v1/projects/kesif-92b61/messages:send'
const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token'
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

// Service Account'dan OAuth2 access token al
async function getAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: SCOPE,
    aud: TOKEN_ENDPOINT,
    iat: now,
    exp: now + 3600,
  }

  const encode = (obj: any) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const signingInput = `${encode(header)}.${encode(payload)}`

  const keyData = serviceAccount.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')

  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const jwt = `${signingInput}.${signatureB64}`

  const tokenRes = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })
  const tokenData = await tokenRes.json()
  return tokenData.access_token
}

// FCM V1 API ile push bildirim gönder
async function sendPush(
  accessToken: string,
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<void> {
  const res = await fetch(FCM_ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        data,
      },
    }),
  })
  if (!res.ok) {
    const err = await res.text()
    throw new Error(`FCM hatası: ${err}`)
  }
}

Deno.serve(async (req) => {
  try {
    const { type, record, table } = await req.json()
    if (type !== 'INSERT') return new Response('OK', { status: 200 })

    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountJson) throw new Error('FIREBASE_SERVICE_ACCOUNT bulunamadı')
    const serviceAccount = JSON.parse(serviceAccountJson)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    let title = '', bodyText = '', receiverId = ''
    let notifData: Record<string, string> = {}

    if (table === 'messages') {
      receiverId = record.receiver_id
      const { data: sender } = await supabase
        .from('profiles').select('nickname').eq('id', record.sender_id).single()
      title = sender?.nickname ?? 'Biri'
      bodyText = record.content ?? 'Yeni mesaj'
      notifData = { type: 'message', sender_id: record.sender_id }

    } else if (table === 'friendships' && record.status === 'pending') {
      receiverId = record.receiver_id
      const { data: sender } = await supabase
        .from('profiles').select('nickname').eq('id', record.sender_id).single()
      title = 'Yeni Arkadaşlık İsteği 👋'
      bodyText = `${sender?.nickname ?? 'Biri'} sana arkadaşlık isteği gönderdi!`
      notifData = { type: 'friend_request', sender_id: record.sender_id }

    } else {
      return new Response('OK', { status: 200 })
    }

    // Alıcının FCM token'ını al
    const { data: receiver } = await supabase
      .from('profiles').select('fcm_token').eq('id', receiverId).single()

    if (!receiver?.fcm_token) {
      console.log('FCM token yok, bildirim gönderilmedi:', receiverId)
      return new Response('No token', { status: 200 })
    }

    const accessToken = await getAccessToken(serviceAccount)
    await sendPush(accessToken, receiver.fcm_token, title, bodyText, notifData)

    console.log('✅ Push bildirim gönderildi')
    return new Response('OK', { status: 200 })
  } catch (err) {
    console.error('Edge Function hatası:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
